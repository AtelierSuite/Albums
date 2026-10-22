import Photos
import SwiftUI

struct PhotosAssetsGrid: View {

    var namespace: Namespace.ID
    var assets: [PHAsset]

    private let batchSize = 200

    @State private var displayCount: Int = 200

    var body: some View {
        PhotosAssetsGridLayout(namespace: namespace,
                               assets: Array(assets.prefix(displayCount)),
                               siblings: assets,
                               hasMore: displayCount < assets.count) {
            displayCount = min(displayCount + batchSize, assets.count)
        }
        .onChange(of: assets.count) {
            displayCount = min(batchSize, assets.count)
        }
    }
}

struct PhotosFetchResultAssetsGrid: View {

    var namespace: Namespace.ID
    var fetchResult: PHFetchResult<PHAsset>

    private let batchSize = 200

    @State private var displayedAssets: [PHAsset] = []

    var body: some View {
        PhotosAssetsGridLayout(namespace: namespace,
                               assets: displayedAssets,
                               siblings: displayedAssets,
                               hasMore: displayedAssets.count < fetchResult.count) {
            loadMoreAssets()
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

struct PhotosAssetsGridLayout: View {

    var namespace: Namespace.ID
    var assets: [PHAsset]
    var siblings: [PHAsset]
    var hasMore: Bool
    var loadMore: () -> Void

    @Environment(PhotosViewerManager.self) var photosViewer
    @Environment(\.openWindow) var openWindow

    @AppStorage(photosPicColumnCountKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var columnCount: Int = 4
    @AppStorage(photosPicViewStyleKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var style: ViewStyle = .grid
    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false

    @State private var gridWidth: CGFloat = 0.0

    var body: some View {
        Group {
            if style == .masonry {
                masonryGrid
            } else {
                PinchZoomGrid(columnCount: fittedColumnCount,
                              itemCount: assets.count,
                              range: GridColumnLimit.pics.range(width: gridWidth),
                              onColumnCountChange: setColumnCount,
                              cachedImage: cachedThumbnail(at:),
                              loadImage: loadThumbnail(at:)) {
                    squareGrid
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            gridWidth = width
        }
    }

    private var fittedColumnCount: Int {
        GridColumnLimit.pics.columns(columnCount, width: gridWidth)
    }

    private func setColumnCount(_ count: Int) {
        columnCount = count
    }

    private func cachedThumbnail(at index: Int) -> UIImage? {
        guard index < assets.count else { return nil }
        return PhotosAssetLabel.cachedThumbnail(for: assets[index])
    }

    private func loadThumbnail(at index: Int) async -> UIImage? {
        guard index < assets.count else { return nil }
        return await PhotosAssetLabel.thumbnail(for: assets[index])
    }

    private var squareGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: fittedColumnCount),
                  spacing: 2.0) {
            ForEach(assets, id: \.localIdentifier) { asset in
                assetCell(for: asset, maintainsAspectRatio: false)
            }
            if hasMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        loadMore()
                    }
            }
        }
    }

    private var masonryGrid: some View {
        VStack(spacing: 0.0) {
            MasonryGrid(items: assets.map { MasonryItem(id: $0.localIdentifier, aspectRatio: $0.aspectRatio) },
                        columnCount: fittedColumnCount,
                        range: GridColumnLimit.pics.range(width: gridWidth),
                        width: gridWidth,
                        onColumnCountChange: setColumnCount) { index in
                assetCell(for: assets[index], maintainsAspectRatio: true)
            } morphCell: { index in
                PhotosAssetLabel(asset: assets[index], maintainsAspectRatio: true)
            }
            if hasMore {
                Color.clear
                    .frame(height: 1)
                    .id(assets.count)
                    .onScrollVisibilityChange { isVisible in
                        if isVisible {
                            loadMore()
                        }
                    }
            }
        }
    }

    private func assetCell(for asset: PHAsset, maintainsAspectRatio: Bool) -> some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Button {
#if targetEnvironment(macCatalyst)
                    if openPicsInNewWindow {
                        openWindow(value: ViewerWindowValue.photo(
                            selectedID: asset.localIdentifier,
                            siblingIDs: siblings.map(\.localIdentifier)))
                    } else {
                        photosViewer.setDisplay(asset, in: siblings)
                    }
#else
                    photosViewer.setDisplay(asset, in: siblings)
#endif
                } label: {
                    PhotosAssetLabel(asset: asset, maintainsAspectRatio: maintainsAspectRatio)
                }
            } else {
                NavigationLink(value: ViewPath.photosAssetViewer(
                    asset: PHAssetWrapper(asset: asset), namespace: namespace)) {
                    PhotosAssetLabel(asset: asset, maintainsAspectRatio: maintainsAspectRatio)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    photosViewer.setDisplay(asset, in: siblings)
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
}

extension PHAsset {
    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 1.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
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
    var maintainsAspectRatio: Bool = false

    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?

    init(asset: PHAsset, maintainsAspectRatio: Bool = false) {
        self.asset = asset
        self.maintainsAspectRatio = maintainsAspectRatio
        _thumbnail = State(initialValue: ThumbnailCache.shared.image(forKey: Self.cacheKey(for: asset)))
    }

    private static func cacheKey(for asset: PHAsset) -> String {
        "PHAsset:\(asset.localIdentifier)"
    }

    static func cachedThumbnail(for asset: PHAsset) -> UIImage? {
        ThumbnailCache.shared.image(forKey: cacheKey(for: asset))
    }

    static func thumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            PHCachingImageManager.default().requestImage(for: asset,
                                                         targetSize: CGSize(width: 256.0, height: 256.0),
                                                         contentMode: .aspectFill,
                                                         options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    var body: some View {
        placeholder
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

    @ViewBuilder
    private var placeholder: some View {
        if maintainsAspectRatio {
            Rectangle()
                .fill(.primary.opacity(0.05))
        } else {
            Rectangle()
                .fill(.primary.opacity(0.05))
                .aspectRatio(1.0, contentMode: .fit)
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
