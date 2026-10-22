import Photos
import SwiftUI

struct PhotosAssetsGrid: View {

    var namespace: Namespace.ID
    var assets: [PHAsset]

    @Environment(PhotosViewerManager.self) var photosViewer
    @Environment(\.openWindow) var openWindow

    private let batchSize = 200

    @AppStorage(wrappedValue: 4, "PicColumnCount",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var columnCount: Int
    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false

    @State private var displayCount: Int = 200

    private var visibleAssets: ArraySlice<PHAsset> {
        assets.prefix(displayCount)
    }

    var body: some View {
        PinchZoomGrid(columnCount: columnCount,
                      itemCount: visibleAssets.count,
                      onColumnCountChange: setColumnCount) {
            grid
        } preview: { index, _ in
            PhotosAssetLabel(asset: assets[index])
        }
        .onChange(of: assets.count) {
            displayCount = min(batchSize, assets.count)
        }
    }

    private func setColumnCount(_ count: Int) {
        columnCount = count
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: columnCount), spacing: 2.0) {
            ForEach(Array(visibleAssets), id: \.localIdentifier) { asset in
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button {
#if targetEnvironment(macCatalyst)
                            if openPicsInNewWindow {
                                openWindow(value: ViewerWindowValue.photo(
                                    selectedID: asset.localIdentifier,
                                    siblingIDs: assets.map(\.localIdentifier)))
                            } else {
                                photosViewer.setDisplay(asset, in: assets)
                            }
#else
                            photosViewer.setDisplay(asset, in: assets)
#endif
                        } label: {
                            PhotosAssetLabel(asset: asset)
                        }
                    } else {
                        NavigationLink(value: ViewPath.photosAssetViewer(
                            asset: PHAssetWrapper(asset: asset), namespace: namespace)) {
                            PhotosAssetLabel(asset: asset)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            photosViewer.setDisplay(asset, in: assets)
                        })
                    }
                }
                .matchedTransitionSource(id: asset.localIdentifier, in: namespace)
                .draggable(PHAssetTransferable(localIdentifier: asset.localIdentifier))
                .contextMenu {
                    PhotosAssetContextMenu(asset: asset)
                }
#if targetEnvironment(macCatalyst)
                .buttonStyle(.borderless)
#else
                .buttonStyle(.plain)
#endif
            }
            if displayCount < assets.count {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        displayCount = min(displayCount + batchSize, assets.count)
                    }
            }
        }
    }
}

struct PhotosFetchResultAssetsGrid: View {

    var namespace: Namespace.ID
    var fetchResult: PHFetchResult<PHAsset>

    @Environment(PhotosViewerManager.self) var photosViewer
    @Environment(\.openWindow) var openWindow

    private let batchSize = 200

    @AppStorage(wrappedValue: 4, "PicColumnCount",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var columnCount: Int
    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false

    @State private var displayedAssets: [PHAsset] = []

    private var hasMore: Bool {
        displayedAssets.count < fetchResult.count
    }

    var body: some View {
        PinchZoomGrid(columnCount: columnCount,
                      itemCount: displayedAssets.count,
                      onColumnCountChange: setColumnCount) {
            grid
        } preview: { index, _ in
            PhotosAssetLabel(asset: displayedAssets[index])
        }
        .onAppear {
            if displayedAssets.isEmpty {
                loadMoreAssets()
            }
        }
        .onChange(of: fetchResult) {
            displayedAssets = []
            loadMoreAssets()
        }
    }

    private func setColumnCount(_ count: Int) {
        columnCount = count
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: columnCount), spacing: 2.0) {
            ForEach(displayedAssets, id: \.localIdentifier) { asset in
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button {
#if targetEnvironment(macCatalyst)
                            if openPicsInNewWindow {
                                openWindow(value: ViewerWindowValue.photo(
                                    selectedID: asset.localIdentifier,
                                    siblingIDs: displayedAssets.map(\.localIdentifier)))
                            } else {
                                photosViewer.setDisplay(asset, in: displayedAssets)
                            }
#else
                            photosViewer.setDisplay(asset, in: displayedAssets)
#endif
                        } label: {
                            PhotosAssetLabel(asset: asset)
                        }
                    } else {
                        NavigationLink(value: ViewPath.photosAssetViewer(
                            asset: PHAssetWrapper(asset: asset), namespace: namespace)) {
                            PhotosAssetLabel(asset: asset)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            photosViewer.setDisplay(asset, in: displayedAssets)
                        })
                    }
                }
                .matchedTransitionSource(id: asset.localIdentifier, in: namespace)
                .draggable(PHAssetTransferable(localIdentifier: asset.localIdentifier))
                .contextMenu {
                    PhotosAssetContextMenu(asset: asset)
                }
#if targetEnvironment(macCatalyst)
                .buttonStyle(.borderless)
#else
                .buttonStyle(.plain)
#endif
            }
            if hasMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        loadMoreAssets()
                    }
            }
        }
    }

    private func loadMoreAssets() {
        let start = displayedAssets.count
        let end = min(start + batchSize, fetchResult.count)
        guard start < end else { return }
        var newAssets: [PHAsset] = []
        newAssets.reserveCapacity(end - start)
        for index in start..<end {
            newAssets.append(fetchResult.object(at: index))
        }
        displayedAssets.append(contentsOf: newAssets)
    }
}

// MARK: - Context Menu

struct PhotosAssetContextMenu: View {

    let asset: PHAsset

    var body: some View {
        if asset.mediaType != .video {
            Button("Shared.Copy", systemImage: "doc.on.doc") {
                let manager = PHCachingImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false
                manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize,
                                     contentMode: .default, options: options) { result, _ in
                    if let result {
                        DispatchQueue.main.async {
                            UIPasteboard.general.image = result
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            MainActor.assumeIsolated {
                                CopiedToast.showCopied()
                            }
                        }
                    }
                }
            }
            ShareLink(item: PHAssetShareable(localIdentifier: asset.localIdentifier),
                      preview: SharePreview(displayName,
                                            image: PHAssetShareable(localIdentifier: asset.localIdentifier))) {
                Label("Shared.Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var displayName: String {
        if let resource = PHAssetResource.assetResources(for: asset).first {
            return resource.originalFilename
        }
        return asset.localIdentifier
    }
}

// MARK: - Share Support

struct PHAssetShareable: Transferable {
    let localIdentifier: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { shareable in
            await withCheckedContinuation { continuation in
                let results = PHAsset.fetchAssets(withLocalIdentifiers: [shareable.localIdentifier], options: nil)
                guard let asset = results.firstObject else {
                    continuation.resume(returning: Data())
                    return
                }
                let manager = PHCachingImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false
                manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize,
                                     contentMode: .default, options: options) { result, _ in
                    if let result, let pngData = result.pngData() {
                        continuation.resume(returning: pngData)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
        }
    }
}

struct PhotosAssetLabel: View {

    let asset: PHAsset

    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?

    init(asset: PHAsset) {
        self.asset = asset
        _thumbnail = State(initialValue: ThumbnailCache.shared.image(forKey: Self.cacheKey(for: asset)))
    }

    private static func cacheKey(for asset: PHAsset) -> String {
        "PHAsset:\(asset.localIdentifier)"
    }

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .aspectRatio(1.0, contentMode: .fit)
            .overlay { geometryOverlay }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(formatDuration(asset.duration))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(4)
                }
            }
            .clipped()
            .contentShape(.rect)
            .clipShape(.rect(cornerRadius: 4.0))
            .onDisappear {
                if let requestID {
                    PHCachingImageManager.default().cancelImageRequest(requestID)
                    self.requestID = nil
                }
                thumbnail = nil
            }
    }

    private var geometryOverlay: some View {
        GeometryReader { metrics in
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.smooth.speed(2)))
                }
            }
            .frame(width: metrics.size.width, height: metrics.size.height)
            .task(id: asset.localIdentifier) {
                loadThumbnail(cellSize: metrics.size)
            }
        }
    }

    private func loadThumbnail(cellSize: CGSize) {
        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: cellSize.width * displayScale,
                                height: cellSize.height * displayScale)

        requestID = manager.requestImage(for: asset, targetSize: targetSize,
                             contentMode: .aspectFill, options: options) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    ThumbnailCache.shared.setImage(result, forKey: Self.cacheKey(for: asset))
                    self.thumbnail = result
                }
            }
        }
    }
}
