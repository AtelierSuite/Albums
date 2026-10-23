import AVKit
import Photos
import SwiftUI

extension PhotosAssetViewer {

    @ViewBuilder
    var shareButton: some View {
        if currentAsset.mediaType == .video {
            if let videoExportURL {
                ShareLink(
                    "Shared.Share",
                    item: videoExportURL,
                    preview: SharePreview(displayName)
                )
            } else {
                Button("Shared.Share", systemImage: "square.and.arrow.up") { }
                    .disabled(true)
            }
        } else {
            ShareLink(
                "Shared.Share",
                item: shareImage,
                preview: SharePreview(
                    displayName,
                    image: shareImage
                )
            )
            .disabled(currentImage == nil)
        }
    }

    @ViewBuilder
    var copyButton: some View {
        if currentAsset.mediaType != .video {
            Button("Shared.Copy", systemImage: "doc.on.doc") {
                if let image = currentImage {
                    UIPasteboard.general.image = image
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    CopiedToast.showCopied()
                }
            }
            .disabled(currentImage == nil)
        }
    }

    @ViewBuilder
    var mainContent: some View {
        if isLandscape {
            HStack(spacing: 0.0) {
                if photosViewer.allAssets.count > 1 {
                    PhotosAssetCarouselStripVertical()
                        .padding(.vertical, fitToScreen ? 0.0 : -8.0)
                }
                imageContent
            }
            .padding(fitToScreen ? 0.0 : 8.0)
            .padding(.leading, fitToScreen ? 0.0 : 40.0)
        } else {
            VStack(alignment: .center, spacing: 0.0) {
                imageContent

                if photosViewer.allAssets.count > 1 {
                    PhotosAssetCarouselStrip()
                        .padding(.top, fitToScreen ? 12.0 : 0.0)
                        .padding(.horizontal, fitToScreen ? 0.0 : -20.0)
                }
            }
            .padding([.top, .horizontal], fitToScreen ? 0.0 : 20.0)
        }
    }

    var imageCornerRadius: CGFloat {
        fitToScreen ? 0.0 : 8.0
    }

    var imageShadowOpacity: CGFloat {
        fitToScreen ? 0.0 : 0.2
    }

    @ViewBuilder
    var imageContent: some View {
        if currentAsset.mediaType == .video {
            videoContent
        } else {
            photoContent
        }
    }

    var videoAspectRatio: CGFloat {
        guard currentAsset.pixelHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(currentAsset.pixelWidth) / CGFloat(currentAsset.pixelHeight)
    }

    var videoContent: some View {
        VStack(spacing: 8.0) {
            Group {
                if let videoPlayer {
                    VideoPlayerView(player: videoPlayer)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: imageCornerRadius))
                } else if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: imageCornerRadius))
                }
            }
            .shadow(color: .black.opacity(imageShadowOpacity), radius: 4.0, x: 0.0, y: 4.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, fitToScreen ? 0.0 : (isLandscape ? 4.0 : 20.0))
        .padding(.bottom, fitToScreen || isLandscape ? 0.0 : 20.0)
        .zIndex(1)
        .onTapGesture {
            withAnimation(.smooth.speed(2)) {
                showImageSize.toggle()
            }
        }
    }

    var photoContent: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: imageCornerRadius))
                        .opacity(isFullImageLoaded ? 0 : 1)
                }
                if let fullImage, isFullImageLoaded {
                    Image(uiImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: imageCornerRadius))
                }
            }

            if showImageSize, let displayedImage = fullImage {
                HStack(alignment: .center, spacing: 2.0) {
                    Text(verbatim: "\(Int(displayedImage.size.width * displayedImage.scale))")
                    Text(verbatim: "×")
                    Text(verbatim: "\(Int(displayedImage.size.height * displayedImage.scale))")
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar, in: .capsule)
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, fitToScreen ? 0.0 : (isLandscape ? 4.0 : 20.0))
        .padding(.bottom, fitToScreen || isLandscape ? 0.0 : 20.0)
        .shadow(color: .black.opacity(imageShadowOpacity), radius: 4.0, x: 0.0, y: 4.0)
        .zIndex(1)
        .offset(displayOffset)
        .scaleEffect(CGSize(width: magnification, height: magnification),
                     anchor: magnificationAnchor)
        .onTapGesture {
            withAnimation(.smooth.speed(2)) {
                showImageSize.toggle()
            }
        }
    }

    func togglePictureInPicture() {
        guard !pipManager.isActive else {
            pipManager.stop()
            return
        }
        guard let image = currentImage else { return }

        let assetToRestore = photosViewer.displayedAsset
        let assetsToRestore = photosViewer.allAssets
        let indexToRestore = photosViewer.currentIndex

        pipManager.start(with: image) { [photosViewer] in
            if let asset = assetToRestore {
                photosViewer.allAssets = assetsToRestore
                photosViewer.currentIndex = indexToRestore
                photosViewer.displayedAsset = asset
            }
        }
    }

    func loadThumbnail() {
        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: viewSize.width * displayScale,
                                height: viewSize.height * displayScale)

        manager.requestImage(for: currentAsset, targetSize: targetSize,
                             contentMode: .aspectFit, options: options) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    self.thumbnail = result
                }
            }
        }
    }

    func loadVideoPlayer() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        PHImageManager.default().requestPlayerItem(
            forVideo: currentAsset, options: options
        ) { playerItem, _ in
            if let playerItem {
                DispatchQueue.main.async {
                    self.videoPlayer = AVPlayer(playerItem: playerItem)
                }
            }
        }
    }

    func exportVideoForSharing() async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let exportSession: AVAssetExportSession? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestExportSession(
                forVideo: currentAsset,
                options: options,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                nonisolated(unsafe) let result = session
                continuation.resume(returning: result)
            }
        }

        guard let exportSession else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard (try? await exportSession.export(to: tempURL, as: .mov)) != nil else { return }
        self.videoExportURL = tempURL
    }

    func loadFullImage() async {
        await withCheckedContinuation { continuation in
            let manager = PHCachingImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            manager.requestImage(for: currentAsset, targetSize: PHImageManagerMaximumSize,
                                 contentMode: .default, options: options) { result, _ in
                if let result {
                    DispatchQueue.main.async {
                        self.fullImage = result
                        self.isFullImageLoaded = true
                    }
                }
                continuation.resume()
            }
        }
    }
}
