import Engine
import SwiftUI

struct AlbumsSection<Content: View>: View {

    @Environment(\.colorScheme) var colorScheme

    @Namespace var albumTransitionNamespace

    var albums: [Album]
    @Binding var style: ViewStyle
    var enablesContextMenu: Bool = true
    var columnCount: Int = 3
    var onColumnCountChange: ((Int) -> Void)?
    var hideSectionHeaders: Bool = false
    var recentlyDeletedCount: Int?
    var isKeptOffline: ((Album) -> Bool)?
    var onToggleOffline: ((Album) -> Void)?
    var onRename: ((Album) -> Void)?
    var onDelete: ((Album) -> Void)?
    var onDrop: (([Drop], Album) -> Void)?
    var onDropFiles: (([URL], Album) -> Void)?
    @ViewBuilder var moveMenu: (Album) -> Content

    @State private var gridWidth: CGFloat = 0.0

    private var fittedColumnCount: Int {
        GridColumnLimit.albums.columns(columnCount, width: gridWidth)
    }

    var body: some View {
        Group {
            switch style {
            case .grid, .masonry:
                PinchZoomGrid(columnCount: fittedColumnCount,
                              itemCount: albums.count + (recentlyDeletedCount == nil ? 0 : 1),
                              range: GridColumnLimit.albums.range(width: gridWidth),
                              columnSpacing: 10.0,
                              rowSpacing: 12.0,
                              onColumnCountChange: onColumnCountChange) { index in
                    pinchZoomCell(at: index)
                } content: {
                    grid
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    gridWidth = width
                }
                .padding(.horizontal, 14.0)
                .padding(.top, hideSectionHeaders ? 0.0 : 10.0)
                .animation(.smooth.speed(2.0), value: fittedColumnCount)
            case .list:
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
            case .carousel:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20.0) {
                        ForEach(albums) { album in
                            NavigationLink(value: ViewPath.album(album: album)) {
                                AlbumGridLabel(namespace: albumTransitionNamespace, album: album, length: 80.0)
                                    .draggable(AlbumTransferable(id: album.id))
                                    .albumDropDestination(onDrop: onDrop, onDropFiles: onDropFiles, album: album)
                            }
                            .id("\(album.identifiableString())")
                            .contextMenu {
                                contextMenu(album)
                            }
                            .buttonStyleAdaptive()
                        }
                        if let recentlyDeletedCount {
                            NavigationLink(value: ViewPath.recentlyDeleted) {
                                RecentlyDeletedAlbumGridLabel(length: 80.0)
                            }
                            .buttonStyleAdaptive()
                        }
                    }
                    .padding(20.0)
                }
                .scrollIndicators(.hidden)
                .frame(height: 120.0)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10.0), count: fittedColumnCount),
                  spacing: 12.0) {
            ForEach(albums) { album in
                NavigationLink(value: ViewPath.album(album: album)) {
                    if enablesContextMenu {
                        AlbumGridLabel(namespace: albumTransitionNamespace, album: album)
                        .draggable(AlbumTransferable(id: album.id))
                        .albumDropDestination(onDrop: onDrop, onDropFiles: onDropFiles, album: album)
                    } else {
                        AlbumGridLabel(namespace: albumTransitionNamespace,
                                       album: album)
                    }
                }
                .id("\(album.identifiableString())")
                .contextMenu {
                    contextMenu(album)
                }
                .buttonStyleAdaptive()
            }
            if recentlyDeletedCount != nil {
                NavigationLink(value: ViewPath.recentlyDeleted) {
                    RecentlyDeletedAlbumGridLabel()
                }
                .buttonStyleAdaptive()
            }
        }
    }

    @ViewBuilder
    private func pinchZoomCell(at index: Int) -> some View {
        if index < albums.count {
            AlbumGridLabel(namespace: nil, album: albums[index])
        } else {
            RecentlyDeletedAlbumGridLabel()
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
