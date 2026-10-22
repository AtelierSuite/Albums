import Engine
import Photos
import SwiftUI

struct PhotosAlbumsSection: View {

    var items: [PHCollectionItem]
    var style: AlbumViewStyle
    var columnCount: Int = 4
    var onColumnCountChange: ((Int) -> Void)?
    var enablesContextMenu: Bool = true
    var onRename: ((PHAssetCollection) -> Void)?
    var onDelete: ((PHAssetCollection) -> Void)?
    var onMoveToFolder: ((PHAssetCollection) -> Void)?
    var onDeleteFolder: ((PHCollectionList) -> Void)?
    var onDropAssets: ((PHAssetTransferable, PHAssetCollection) -> Void)?
    var coverRefreshID: Int = 0

    @Namespace var albumTransitionNamespace

    @State private var containerWidth: CGFloat = 0.0

    var body: some View {
        Group {
            if style.isGrid {
                pinchZoomGrid
            } else if style.isCarousel {
                carousel
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
    }

    private var metrics: AlbumLayoutMetrics {
        AlbumLayoutMetrics(style: style, containerWidth: containerWidth, columnCount: columnCount)
    }

    private var pinchZoomGrid: some View {
        let metrics = metrics
        let labelStyle = metrics.gridLabelStyle
        return PinchZoomGrid(columnCount: metrics.fittedColumnCount,
                             itemCount: items.count,
                             range: metrics.gridColumnRange,
                             columnSpacing: metrics.gridColumnSpacing,
                             rowSpacing: metrics.gridRowSpacing,
                             onColumnCountChange: onColumnCountChange) { index in
            PhotosCollectionGridLabel(item: items[index], style: labelStyle,
                                      coverRefreshID: coverRefreshID)
        } content: {
            LazyVGrid(columns: metrics.gridColumns, spacing: metrics.gridRowSpacing) {
                ForEach(items) { item in
                    itemLink(for: item) {
                        PhotosCollectionGridLabel(namespace: albumTransitionNamespace, item: item,
                                                  style: labelStyle, coverRefreshID: coverRefreshID)
                            .photosAlbumDropDestination(item: item, onDropAssets: onDropAssets)
                    }
                    .contextMenu { contextMenu(for: item) }
                    .buttonStyleAdaptive()
                }
            }
        }
        .padding(.horizontal, metrics.gridHorizontalPadding)
        .padding(.top, 10.0)
        .animation(.smooth.speed(2.0), value: metrics.fittedColumnCount)
        .animation(.smooth.speed(2.0), value: style)
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0.0) {
            ForEach(items) { item in
                itemLink(for: item) {
                    PhotosCollectionListRow(namespace: albumTransitionNamespace, item: item,
                                            coverRefreshID: coverRefreshID)
                        .photosAlbumDropDestination(item: item, onDropAssets: onDropAssets)
                }
                .contextMenu { contextMenu(for: item) }
                .buttonStyleAdaptive()
                if item.id != items.last?.id {
                    Divider()
                        .padding([.leading], 84.0)
                }
            }
        }
    }

    private var carousel: some View {
        let metrics = metrics
        let length = metrics.carouselCoverLength
        let labelStyle = metrics.carouselLabelStyle
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: metrics.carouselSpacing) {
                ForEach(items) { item in
                    itemLink(for: item) {
                        Group {
                            if style == .compactCarousel {
                                PhotosCollectionChipLabel(namespace: albumTransitionNamespace, item: item,
                                                          coverRefreshID: coverRefreshID)
                            } else {
                                PhotosCollectionGridLabel(namespace: albumTransitionNamespace, item: item,
                                                          length: length, style: labelStyle,
                                                          coverRefreshID: coverRefreshID)
                            }
                        }
                        .photosAlbumDropDestination(item: item, onDropAssets: onDropAssets)
                    }
                    .contextMenu { contextMenu(for: item) }
                    .buttonStyleAdaptive()
                }
            }
            .padding(.horizontal, 20.0)
            .padding(.vertical, 10.0)
        }
        .scrollIndicators(.hidden)
        .albumCarouselPinch(columnCount: columnCount, style: style, onColumnCountChange: onColumnCountChange)
        .animation(.smooth.speed(2.0), value: columnCount)
        .animation(.smooth.speed(2.0), value: style)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for item: PHCollectionItem) -> some View {
        if enablesContextMenu {
            switch item {
            case .album(let collection):
                if let onMoveToFolder {
                    Button(String(localized: "Photos.MoveToFolder", table: "Photos"), systemImage: "folder") {
                        onMoveToFolder(collection)
                    }
                }
                if let onRename {
                    Divider()
                    Button("Shared.Rename", systemImage: "pencil") {
                        onRename(collection)
                    }
                }
                if let onDelete {
                    Divider()
                    Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                        onDelete(collection)
                    }
                }
            case .folder(let folder):
                if let onDeleteFolder {
                    Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                        onDeleteFolder(folder)
                    }
                }
            }
        }
    }

    // MARK: - Navigation Links

    @ViewBuilder
    private func itemLink<Label: View>(
        for item: PHCollectionItem,
        @ViewBuilder label: () -> Label
    ) -> some View {
        switch item {
        case .album(let collection):
            NavigationLink(value: ViewPath.photosAlbum(
                album: PHAssetCollectionWrapper(collection: collection))) {
                label()
            }
        case .folder(let folder):
            NavigationLink(value: ViewPath.photosFolder(
                folder: PHCollectionListWrapper(collectionList: folder))) {
                label()
            }
        }
    }
}

// MARK: - Labels

struct PhotosCollectionCover: View {

    var item: PHCollectionItem
    var length: CGFloat?
    var style: AlbumCoverStyle = .stack
    var coverRefreshID: Int = 0

    var body: some View {
        switch item {
        case .album(let collection):
            AlbumCover.AsyncPhotosAlbumCover(collection: collection, length: length,
                                             refreshID: coverRefreshID, style: style)
        case .folder(let folder):
            AlbumCover.AsyncPhotosFolderCover(folder: folder, length: length, style: style)
        }
    }
}

struct PhotosCollectionCounts {
    var picCount: Int = 0
    var albumCount: Int = 0
}

extension PHCollectionItem {
    var displayTitle: String {
        title.isEmpty ? String(localized: "Import.Albums.Untitled", table: "Import") : title
    }
}

extension View {
    func loadsCounts(of item: PHCollectionItem, refreshID: Int,
                     into counts: Binding<PhotosCollectionCounts>) -> some View {
        task(id: "\(item.id)-\(refreshID)") {
            counts.wrappedValue = PhotosCollectionCounts(picCount: item.picCount, albumCount: item.albumCount)
        }
    }
}

struct PhotosCollectionGridLabel: View {

    var namespace: Namespace.ID?
    var item: PHCollectionItem
    var length: CGFloat?
    var style = AlbumLabelStyle()
    var coverRefreshID: Int = 0

    @State private var counts = PhotosCollectionCounts()

    var body: some View {
        AlbumGridLabelLayout(namespace: namespace, id: item.id, title: item.displayTitle,
                             picCount: counts.picCount, albumCount: counts.albumCount,
                             length: length, style: style) {
            PhotosCollectionCover(item: item, length: length, style: style.cover,
                                  coverRefreshID: coverRefreshID)
        }
        .loadsCounts(of: item, refreshID: coverRefreshID, into: $counts)
    }
}

struct PhotosCollectionChipLabel: View {

    var namespace: Namespace.ID?
    var item: PHCollectionItem
    var coverRefreshID: Int = 0

    @State private var counts = PhotosCollectionCounts()

    var body: some View {
        AlbumChipLabelLayout(namespace: namespace, id: item.id, title: item.displayTitle,
                             picCount: counts.picCount, albumCount: counts.albumCount) {
            PhotosCollectionCover(item: item, length: 40.0, style: .flat(cornerRadius: 9.0),
                                  coverRefreshID: coverRefreshID)
        }
        .loadsCounts(of: item, refreshID: coverRefreshID, into: $counts)
    }
}

struct PhotosCollectionListRow: View {

    var namespace: Namespace.ID?
    var item: PHCollectionItem
    var coverRefreshID: Int = 0

    @State private var counts = PhotosCollectionCounts()

    var body: some View {
        AlbumListRowLayout(namespace: namespace, id: item.id, title: item.displayTitle) {
            PhotosCollectionCover(item: item, length: 48.0, coverRefreshID: coverRefreshID)
        } detail: {
            AlbumCountText(picCount: counts.picCount, albumCount: counts.albumCount)
        }
        .loadsCounts(of: item, refreshID: coverRefreshID, into: $counts)
    }
}

// MARK: - Drop Destination

extension View {
    @ViewBuilder
    func photosAlbumDropDestination(
        item: PHCollectionItem,
        onDropAssets: ((PHAssetTransferable, PHAssetCollection) -> Void)?
    ) -> some View {
        switch item {
        case .album(let collection):
            if let onDropAssets {
                self.dropDestination(for: PHAssetTransferable.self) { items, _ in
                    for transferable in items {
                        onDropAssets(transferable, collection)
                    }
                    return !items.isEmpty
                }
            } else {
                self
            }
        case .folder:
            self
        }
    }
}
