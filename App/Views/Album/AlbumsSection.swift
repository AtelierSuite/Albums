import Engine
import SwiftUI

struct AlbumsSection<Content: View>: View {

    @Environment(\.colorScheme) var colorScheme

    @Namespace var albumTransitionNamespace

    var albums: [Album]
    var style: AlbumViewStyle
    var enablesContextMenu: Bool = true
    var columnCount: Int = 3
    var hideSectionHeaders: Bool = false
    var recentlyDeletedCount: Int?
    var isKeptOffline: ((Album) -> Bool)?
    var onToggleOffline: ((Album) -> Void)?
    var onRename: ((Album) -> Void)?
    var onDelete: ((Album) -> Void)?
    var onDrop: (([Drop], Album) -> Void)?
    var onDropFiles: (([URL], Album) -> Void)?
    @ViewBuilder var moveMenu: (Album) -> Content

    @State private var containerWidth: CGFloat = 0.0

    var body: some View {
        Group {
            if style.isGrid {
                grid
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

    var gridHorizontalPadding: CGFloat {
        style == .stackedGrid ? 14.0 : 16.0
    }

    var gridColumnSpacing: CGFloat {
        style == .stackedGrid ? 10.0 : 12.0
    }

    var gridCoverWidth: CGFloat {
        let count = CGFloat(max(columnCount, 1))
        return (containerWidth - gridHorizontalPadding * 2.0 - gridColumnSpacing * (count - 1.0)) / count
    }

    var carouselCoverLength: CGFloat {
        let baseLength: CGFloat = style == .plainCarousel ? 132.0 : 80.0
        return baseLength * 4.0 / CGFloat(min(max(columnCount, 2), 6))
    }

    var grid: some View {
        let labelStyle = AlbumLabelStyle(viewStyle: style, coverWidth: gridCoverWidth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridColumnSpacing,
                                                            alignment: .top),
                                        count: columnCount),
                         spacing: style == .stackedGrid ? 12.0 : 14.0) {
            ForEach(albums) { album in
                NavigationLink(value: ViewPath.album(album: album)) {
                    gridLabel(album, style: labelStyle)
                }
                .id("\(album.identifiableString())")
                .contextMenu {
                    contextMenu(album)
                }
                .buttonStyleAdaptive()
            }
            if recentlyDeletedCount != nil {
                NavigationLink(value: ViewPath.recentlyDeleted) {
                    RecentlyDeletedAlbumGridLabel(style: labelStyle)
                }
                .buttonStyleAdaptive()
            }
        }
        .padding(.horizontal, gridHorizontalPadding)
        .padding(.top, hideSectionHeaders ? 0.0 : 10.0)
        .animation(.smooth.speed(2.0), value: columnCount)
        .animation(.smooth.speed(2.0), value: style)
    }

    var list: some View {
        LazyVStack(alignment: .leading, spacing: 0.0) {
            ForEach(albums) { album in
                NavigationLink(value: ViewPath.album(album: album)) {
                    AlbumListRow(namespace: albumTransitionNamespace, album: album)
                        .draggable(AlbumTransferable(id: album.id))
                        .albumDropDestination(onDrop: onDrop, onDropFiles: onDropFiles, album: album)
                }
                .id("\(album.identifiableString())")
                .contextMenu {
                    contextMenu(album)
                }
                .buttonStyleAdaptive()
                if album != albums.last || recentlyDeletedCount != nil {
                    Divider()
                        .padding([.leading], 84.0)
                }
            }
            if let recentlyDeletedCount {
                NavigationLink(value: ViewPath.recentlyDeleted) {
                    RecentlyDeletedAlbumListRow(count: recentlyDeletedCount)
                }
                .buttonStyleAdaptive()
            }
        }
    }

    var carouselItems: [AlbumsSectionItem] {
        albums.map { .album($0) } + (recentlyDeletedCount.map { [.recentlyDeleted(count: $0)] } ?? [])
    }

    var carousel: some View {
        let length = carouselCoverLength
        let labelStyle = AlbumLabelStyle(viewStyle: style, coverWidth: length)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: style == .stackedCarousel ? 20.0 : 12.0) {
                ForEach(carouselItems) { item in
                    carouselItem(item, length: length, labelStyle: labelStyle)
                }
            }
            .padding(.horizontal, 20.0)
            .padding(.vertical, 10.0)
        }
        .scrollIndicators(.hidden)
        .animation(.smooth.speed(2.0), value: columnCount)
        .animation(.smooth.speed(2.0), value: style)
    }

    @ViewBuilder
    func carouselItem(_ item: AlbumsSectionItem, length: CGFloat, labelStyle: AlbumLabelStyle) -> some View {
        switch item {
        case .album(let album):
            NavigationLink(value: ViewPath.album(album: album)) {
                Group {
                    if style == .compactCarousel {
                        AlbumChipLabel(namespace: albumTransitionNamespace, album: album)
                    } else {
                        AlbumGridLabel(namespace: albumTransitionNamespace, album: album,
                                       length: length, style: labelStyle)
                    }
                }
                .draggable(AlbumTransferable(id: album.id))
                .albumDropDestination(onDrop: onDrop, onDropFiles: onDropFiles, album: album)
            }
            .id("\(album.identifiableString())")
            .contextMenu {
                contextMenu(album)
            }
            .buttonStyleAdaptive()
        case .recentlyDeleted(let count):
            NavigationLink(value: ViewPath.recentlyDeleted) {
                if style == .compactCarousel {
                    RecentlyDeletedAlbumChipLabel(count: count)
                } else {
                    RecentlyDeletedAlbumGridLabel(length: length, style: labelStyle)
                }
            }
            .buttonStyleAdaptive()
        }
    }

    @ViewBuilder
    func gridLabel(_ album: Album, style labelStyle: AlbumLabelStyle) -> some View {
        if enablesContextMenu {
            AlbumGridLabel(namespace: albumTransitionNamespace, album: album, style: labelStyle)
                .draggable(AlbumTransferable(id: album.id))
                .albumDropDestination(onDrop: onDrop, onDropFiles: onDropFiles, album: album)
        } else {
            AlbumGridLabel(namespace: albumTransitionNamespace, album: album, style: labelStyle)
        }
    }

    @ViewBuilder
    func contextMenu(_ album: Album) -> some View {
        if enablesContextMenu {
            moveMenu(album)
            if let onToggleOffline {
                Divider()
                if isKeptOffline?(album) == true {
                    Button("Shared.RemoveDownload", systemImage: "icloud.slash") {
                        onToggleOffline(album)
                    }
                } else {
                    Button("Shared.Download", systemImage: "arrow.down.circle") {
                        onToggleOffline(album)
                    }
                }
            }
            if album.hasCoverPhoto {
                Divider()
                Button("Shared.ResetCover", systemImage: "photo") {
                    Task {
                        await DataActor.shared.updateAlbumCover(forAlbumWithID: album.id, coverData: nil)
                        AlbumCoverCache.shared.removeImages(forAlbumID: album.id)
                    }
                }
            }
            if onRename != nil || onDelete != nil {
                Divider()
            }
            if let onRename {
                Button("Shared.Rename", systemImage: "pencil") {
                    onRename(album)
                }
            }
            if let onDelete {
                Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                    onDelete(album)
                }
            }
        }
    }
}

enum AlbumsSectionItem: Identifiable {
    case album(Album)
    case recentlyDeleted(count: Int)

    var id: String {
        switch self {
        case .album(let album): album.identifiableString()
        case .recentlyDeleted: "RecentlyDeleted"
        }
    }
}
