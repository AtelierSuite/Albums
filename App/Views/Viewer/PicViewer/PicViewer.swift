import AVKit
import Engine
import SwiftUI

struct PicViewer: View {

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.dismiss) var dismiss
    @Environment(ViewerManager.self) var viewer
    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(PictureInPictureManager.self) var pipManager

    @AppStorage(viewerFitToScreenKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var fitToScreen: Bool = false
    @AppStorage(viewerBackgroundTypeKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var backgroundType: ViewerBackgroundType = .immersive
    @AppStorage(viewerShowResolutionKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var showResolutionByDefault: Bool = true

    var pic: Pic

    @State var displayOffset: CGSize = .zero
    @State var magnification: CGFloat = 1.0
    @State var magnificationAnchor: UnitPoint = .center
    @State var containingAlbumName: String?
    @State var showImageSize: Bool = true
    @State var showDownloadFailedPopover: Bool = false
    @State var isRenamePicPresented: Bool = false
    @State var isConfirmingDeletePic: Bool = false
    @State var renamePicText: String = ""
    @State var displayedPicName: String = ""
    @State var isDisplayedPicPinned: Bool = false
    @State var videoResolution: CGSize?
    @State var swipeOffset: CGFloat = 0.0
    @State var swipeBase: CGFloat = 0.0
    @State var isSwipeTracking: Bool = false
    @State var swipeContentWidth: CGFloat = 0.0
    @State var pendingSwipeTarget: Int?
    @State var photoContainerSize: CGSize = .zero

    var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var canShowInAlbum: Bool {
        guard viewer.allowsShowInAlbum, let displayedPic = viewer.displayedPic else { return false }
        return viewer.origin != .album(id: displayedPic.containingAlbumID)
    }

    var currentImage: UIImage? {
        viewer.displayedImage ?? viewer.displayedThumbnail
    }

    var shareImage: Image {
        Image(uiImage: currentImage ?? UIImage())
    }

    var body: some View {
        mainContent
        .frame(maxHeight: .infinity)
        .background {
            SwipeBackGestureDisabler()
                .frame(width: 0.0, height: 0.0)
        }
        .background {
            switch backgroundType {
            case .immersive:
                if let backgroundImage = currentImage {
                    Canvas { [edit = displayedOrientationEdit.normalized] context, size in
                        context.addFilter(.blur(radius: 40))
                        context.addFilter(.brightness(colorScheme == .dark ? -0.5 : 0.1))
                        let image = Image(uiImage: backgroundImage)
                        let imageSize = backgroundImage.size
                        let drawnSize = edit.swapsDimensions
                            ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
                        let scaleX = size.width / drawnSize.width
                        let scaleY = size.height / drawnSize.height
                        let scale = max(scaleX, scaleY)
                        let drawWidth = imageSize.width * scale
                        let drawHeight = imageSize.height * scale
                        context.translateBy(x: size.width / 2, y: size.height / 2)
                        context.scaleBy(x: edit.isMirrored ? -1.0 : 1.0, y: 1.0)
                        context.rotate(by: .degrees(Double(edit.quarterTurns) * -90.0))
                        let drawRect = CGRect(
                            x: -drawWidth / 2,
                            y: -drawHeight / 2,
                            width: drawWidth,
                            height: drawHeight
                        )
                        context.draw(image, in: drawRect)
                    }
                    .ignoresSafeArea()
                }
            case .followSystem:
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            case .dark:
                Color.black
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            ToastOverlayView(priority: 1) {
                navigation.signalDataChanged()
            }
        }
        .navigationTitle(displayedPicName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("ViewTitle.Pics.Rename", isPresented: $isRenamePicPresented) {
            TextField(displayedPicName, text: $renamePicText)
                .textInputAutocapitalization(.words)
            Button("Shared.Rename") {
                let newName = renamePicText.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty, let picID = viewer.displayedPic?.id else { return }
                Task {
                    await DataActor.shared.renamePic(withID: picID, to: newName)
                    viewer.displayedPic?.name = newName
                    if let index = viewer.allPics.firstIndex(where: { $0.id == picID }) {
                        viewer.allPics[index].name = newName
                    }
                    withAnimation(.smooth.speed(2.0)) {
                        displayedPicName = newName
                    }
                }
            }
            Button("Shared.Cancel", role: .cancel) { }
        }
        .confirmationDialog("Shared.DeleteConfirmation.Pic", isPresented: $isConfirmingDeletePic,
                            titleVisibility: .visible) {
            Button("Shared.Delete", role: .destructive) {
                deleteDisplayedPic()
            }
            Button("Shared.Cancel", role: .cancel) { }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2.0) {
                    Button {
                        renamePicText = displayedPicName
                        isRenamePicPresented = true
                    } label: {
                        Text(displayedPicName)
                            .font(.headline)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.plain)
                    if let containingAlbumName {
                        Text(containingAlbumName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if pipManager.isPossible, viewer.displayedPic?.isVideo != true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shared.PictureInPicture",
                           systemImage: pipManager.isActive ? "pip.exit" : "pip.enter") {
                        togglePictureInPicture()
                    }
                    .disabled(currentImage == nil || isEditingOrientation)
                }
            }
            if isLandscape {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    shareButton
                    if viewer.displayedPic?.isVideo != true {
                        rotateButton
                        flipButton
                    }
                    copyButton
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    shareButton
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                if viewer.displayedPic?.isVideo != true {
                    ToolbarItemGroup(placement: .bottomBar) {
                        rotateButton
                        flipButton
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                }
                ToolbarItem(placement: .bottomBar) {
                    copyButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Shared.More", systemImage: "ellipsis") {
                    if viewer.allowsPinning {
                        PinButton(isPinned: isDisplayedPicPinned) {
                            toggleDisplayedPicPin()
                        }
                    }
                    Button("Shared.Rename", systemImage: "pencil") {
                        renamePicText = displayedPicName
                        isRenamePicPresented = true
                    }
                    if canShowInAlbum {
                        Button("Shared.ShowInAlbum", systemImage: "rectangle.stack") {
                            showInAlbum()
                        }
                    }
                    Divider()
                    deleteButton
                }
            }
        }
        .toolbar(isLandscape ? .hidden : .automatic, for: .bottomBar)
        .onAppear {
            showImageSize = showResolutionByDefault
        }
        .task(id: viewer.displayedPicID) {
            displayedPicName = viewer.displayedPic?.name ?? pic.name
            isDisplayedPicPinned = viewer.displayedPic?.isPinned ?? pic.isPinned
            containingAlbumName = nil
            videoResolution = nil
            if let albumID = viewer.displayedPic?.containingAlbumID ?? pic.containingAlbumID {
                let name = await DataActor.shared.album(for: albumID)?.name
                await MainActor.run {
                    withAnimation(.smooth.speed(2.0)) {
                        self.containingAlbumName = name
                    }
                }
            }
            if viewer.displayedPic?.isVideo == true, let videoURL = viewer.displayedVideoURL {
                let asset = AVURLAsset(url: videoURL)
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try? await track.load(.naturalSize)
                    let transform = try? await track.load(.preferredTransform)
                    if let size, let transform {
                        let transformed = size.applying(transform)
                        videoResolution = CGSize(
                            width: abs(transformed.width),
                            height: abs(transformed.height)
                        )
                    } else if let size {
                        videoResolution = size
                    }
                }
            }
        }
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
#if targetEnvironment(macCatalyst)
        .focusable()
        .onKeyPress(.leftArrow) {
            viewer.navigateToPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewer.navigateToNext()
            return .handled
        }
#endif
    }
}
