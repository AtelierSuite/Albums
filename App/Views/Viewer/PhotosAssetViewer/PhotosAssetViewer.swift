import AVKit
import Photos
import SwiftUI

struct PhotosAssetViewer: View {

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(PhotosViewerManager.self) var photosViewer
    @EnvironmentObject var navigation: NavigationManager
    @Environment(PictureInPictureManager.self) var pipManager

    let asset: PHAsset

    @Environment(\.displayScale) var displayScale

    @State var thumbnail: UIImage?
    @State var fullImage: UIImage?
    @State var isFullImageLoaded: Bool = false
    @State var showImageSize: Bool = true
    @State var magnification: CGFloat = 1.0
    @State var magnificationAnchor: UnitPoint = .center
    @State var displayOffset: CGSize = .zero
    @State var viewSize: CGSize = .zero
    @State var videoPlayer: AVPlayer?
    @State var videoExportURL: URL?

    var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var currentAsset: PHAsset {
        photosViewer.displayedAsset ?? asset
    }

    var currentImage: UIImage? {
        fullImage ?? thumbnail
    }

    var shareImage: Image {
        if let image = currentImage, let cgImage = image.cgImage {
            Image(cgImage, scale: image.scale, label: Text(""))
        } else {
            Image(uiImage: UIImage())
        }
    }

    var displayName: String {
        if let resource = PHAssetResource.assetResources(for: currentAsset).first {
            return resource.originalFilename
        }
        return currentAsset.localIdentifier
    }

    var body: some View {
        mainContent
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewSize = newSize
        }
        .background {
            if let backgroundImage = currentImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .overlay {
                        Color(colorScheme == .dark ? .black : .white)
                            .opacity(0.3)
                    }
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            ToastOverlayView(priority: 1) {
                navigation.signalDataChanged()
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let creationDate = currentAsset.creationDate {
                ToolbarItem(placement: .subtitle) {
                    Text(creationDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if pipManager.isPossible, currentAsset.mediaType != .video {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shared.PictureInPicture",
                           systemImage: pipManager.isActive ? "pip.exit" : "pip.enter") {
                        togglePictureInPicture()
                    }
                    .disabled(currentImage == nil)
                }
            }
            if isLandscape {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    shareButton
                    copyButton
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    shareButton
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    copyButton
                }
            }
        }
        .toolbar(isLandscape ? .hidden : .automatic, for: .bottomBar)
        .task(id: currentAsset.localIdentifier) {
            isFullImageLoaded = false
            videoPlayer?.pause()
            videoPlayer = nil
            videoExportURL = nil
            if currentAsset.mediaType == .video {
                loadThumbnail()
                loadVideoPlayer()
                await exportVideoForSharing()
            } else {
                loadThumbnail()
                await loadFullImage()
            }
        }
#if targetEnvironment(macCatalyst)
        .focusable()
        .onKeyPress(.leftArrow) {
            withAnimation(.smooth.speed(2)) {
                photosViewer.navigateToPrevious()
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            withAnimation(.smooth.speed(2)) {
                photosViewer.navigateToNext()
            }
            return .handled
        }
#else
        .gesture(
            MagnifyGesture()
                .onChanged { gesture in
                    if gesture.magnification > 1.0 {
                        magnification = gesture.magnification
                        magnificationAnchor = gesture.startAnchor
                    } else {
                        magnification = 1.0
                    }
                }
                .onEnded { _ in
                    doWithAnimation {
                        magnification = 1.0
                        displayOffset = .zero
                    } completion: {
                        magnificationAnchor = .center
                    }
                }
        )
#endif
    }
}
