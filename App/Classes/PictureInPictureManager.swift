import AVFoundation
import AVKit
import CoreMedia
import SwiftUI

@MainActor @Observable
class PictureInPictureManager: NSObject {

    var isActive: Bool = false
    /// Set synchronously when `start()` is called so parent views can dismiss the viewer.
    var isPreparing: Bool = false

    @ObservationIgnored var onRestore: (@MainActor () -> Void)?
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var playerLooper: AVPlayerLooper?
    @ObservationIgnored private(set) var playerLayer = AVPlayerLayer()
    @ObservationIgnored private var pipPossibleObservation: NSKeyValueObservation?

    var isPossible: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func setup() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        self.player = player

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    /// Called by the layer view once the player layer is attached to the window.
    func layerDidMoveToWindow() {
        guard pipController == nil, player != nil else { return }
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        pipController?.requiresLinearPlayback = true
        #if targetEnvironment(macCatalyst)
        pipController?.setValue(2, forKey: "controlsStyle")
        #else
        pipController?.setValue(1, forKey: "controlsStyle")
        #endif
    }

    func start(with image: UIImage, restore: @escaping @MainActor () -> Void) {
        guard pipController != nil, player != nil, !isActive else { return }

        onRestore = restore
        isPreparing = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            debugPrint("PiP: Failed to configure audio session: \(error)")
        }

        Task.detached(priority: .userInitiated) {
            guard let videoURL = Self.createVideo(from: image) else {
                await MainActor.run { self.isPreparing = false }
                return
            }
            await MainActor.run {
                guard let pipController = self.pipController,
                      let player = self.player else { return }

                let asset = AVURLAsset(url: videoURL)
                let item = AVPlayerItem(asset: asset)

                player.removeAllItems()
                self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
                player.play()

                UIApplication.shared.isIdleTimerDisabled = true

                // Wait until the PiP controller reports that PiP is possible
                // before actually starting it; starting too early silently fails.
                if pipController.isPictureInPicturePossible {
                    pipController.startPictureInPicture()
                } else {
                    self.pipPossibleObservation = pipController.observe(
                        \.isPictureInPicturePossible,
                        options: [.new]
                    ) { [weak self] _, change in
                        guard change.newValue == true else { return }
                        Task { @MainActor [weak self] in
                            self?.pipPossibleObservation = nil
                            self?.pipController?.startPictureInPicture()
                        }
                    }
                }
            }
        }
    }

    func stop() {
        pipController?.stopPictureInPicture()
    }

    private func didStop() {
        isActive = false
        isPreparing = false
        onRestore = nil
        pipPossibleObservation = nil
        player?.pause()
        player?.removeAllItems()
        playerLooper = nil
        UIApplication.shared.isIdleTimerDisabled = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            debugPrint("PiP: Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Video Creation

    private nonisolated static func createVideo(from image: UIImage) -> URL? {
        guard let cgImage = uprightCGImage(from: image) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        // Dimensions must be even for H.264.
        let evenWidth = width % 2 == 0 ? width : width - 1
        let evenHeight = height % 2 == 0 ? height : height - 1

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return nil
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: evenWidth,
                kCVPixelBufferHeightKey as String: evenHeight
            ]
        )

        writer.add(writerInput)

        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBuffer = createPixelBuffer(from: cgImage,
                                                  width: evenWidth,
                                                  height: evenHeight) else {
            writer.cancelWriting()
            return nil
        }

        // Write two identical frames to produce a 1-hour video.
        let oneHour = CMTime(value: 3600, timescale: 1)
        adaptor.append(pixelBuffer, withPresentationTime: .zero)
        adaptor.append(pixelBuffer, withPresentationTime: oneHour)

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        return writer.status == .completed ? outputURL : nil
    }

    private nonisolated static func uprightCGImage(from image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }

    private nonisolated static func createPixelBuffer(
        from cgImage: CGImage, width: Int, height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            isPreparing = false
            isActive = true
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        debugPrint("PiP: Failed to start: \(error)")
        Task { @MainActor in
            isPreparing = false
            didStop()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            didStop()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        nonisolated(unsafe) let handler = completionHandler
        Task { @MainActor in
            onRestore?()
            handler(true)
        }
    }
}

// MARK: - SwiftUI Wrapper

struct PictureInPictureLayerView: UIViewRepresentable {
    let pipManager: PictureInPictureManager

    func makeUIView(context: UIViewRepresentableContext<PictureInPictureLayerView>) -> PictureInPictureHostView {
        let container = PictureInPictureHostView(pipManager: pipManager)
        container.clipsToBounds = true
        container.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let playerLayer = pipManager.playerLayer
        playerLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        container.layer.addSublayer(playerLayer)
        return container
    }

    func updateUIView(_ uiView: PictureInPictureHostView,
                      context: UIViewRepresentableContext<PictureInPictureLayerView>) {}
}

class PictureInPictureHostView: UIView {
    private let pipManager: PictureInPictureManager

    init(pipManager: PictureInPictureManager) {
        self.pipManager = pipManager
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            Task { @MainActor in
                pipManager.layerDidMoveToWindow()
            }
        }
    }
}
