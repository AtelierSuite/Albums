import Engine
import SwiftUI

extension AlbumView {
    var albumSection: some View {
        Group {
            if !hideSectionHeaders {
                Group {
#if targetEnvironment(macCatalyst)
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: albums.count)
#else
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                      count: albums.count)
                    } else {
                        SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                      count: albums.count) {
                            AlbumViewStylePicker(selection: $albumStyleState)
                            AlbumSortPicker(selection: $albumSortState)
                        }
                    }
#endif
                }
                .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if hasAlbumItems {
                AlbumsSection(albums: albums, style: albumStyleState,
                             columnCount: albumColumnCount,
                             onColumnCountChange: setAlbumColumnCount,
                             hideSectionHeaders: hideSectionHeaders,
                             recentlyDeletedCount: showsRecentlyDeletedAlbum ? recentlyDeletedCount : nil,
                             isKeptOffline: { OfflineAlbums.contains($0.id) },
                             onToggleOffline: {
                                 OfflineAlbums.toggle($0.id, in: DataActor.shared.collectionID)
                             }) { album in
                    renameAlbumText = album.name
                    albumToRename = album
                } onDelete: { album in
                    deleteAlbum(album)
                } onDrop: { drops, album in
                    moveDropToAlbum(drops, to: album)
                } onDropFiles: { urls, album in
                    importFiles(urls, into: album)
                } moveMenu: { album in
                    AlbumMoveMenu(album: album, totalAlbumCount: totalAlbumCount) {
                        refreshAlbumsAndSet()
                    } onOtherLibraries: {
                        movePayload = .album(album)
                    }
                }
            } else if !hideSectionHeaders {
                Text("Albums.NoAlbums", tableName: "Albums")
                    .foregroundStyle(.secondary)
                    .padding(20.0)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func setAlbumColumnCount(_ count: Int) {
        albumColumnCount = count
    }

    func setPicColumnCount(_ count: Int) {
        columnCount = count
    }

    var showsRecentlyDeletedAlbum: Bool {
        currentAlbum == nil && !isSearching && hasFetchedAlbums
    }

    var hasAlbumItems: Bool {
        !albums.isEmpty || showsRecentlyDeletedAlbum
    }

    var picsSection: some View {
        Group {
            if !hideSectionHeaders {
                Group {
#if targetEnvironment(macCatalyst)
                    SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"),
                                  count: hasFetchedPicCount ? picCount : pics.count)
#else
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"),
                                      count: hasFetchedPicCount ? picCount : pics.count)
                    } else {
                        SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"),
                                      count: hasFetchedPicCount ? picCount : pics.count) {
                            Button(
                                String(localized: "Duplicates.FindDuplicates", table: "Photos"),
                                systemImage: "photo.stack"
                            ) {
                                isDuplicateCheckerPresented = true
                            }
                            Button(
                                String(localized: "Sort.SortIntelligently", table: "Photos"),
                                systemImage: "wand.and.stars"
                            ) {
                                isIntelligentSortPresented = true
                            }
                            Divider()
                            PicSortPicker(selection: $picSortType)
                            PicViewStylePicker(selection: $picViewStyle)
                        }
                    }
#endif
                }
                .disabled(isSelectingPics)
                .opacity(isSelectingPics ? 0.5 : 1.0)
                .animation(.smooth.speed(2.0), value: isSelectingPics)
                .padding(EdgeInsets(top: 0.0,
                                    leading: 20.0,
                                    bottom: 6.0,
                                    trailing: 20.0))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if hasFetchedPicCount && picCount > 0 {
                PicsGrid(namespace: namespace, pics: pics,
                         placeholderCount: max(picCount - pics.count, 0),
                         isSelecting: $isSelectingPics,
                         columnCount: columnCount,
                         onColumnCountChange: setPicColumnCount,
                         style: picViewStyle,
                         highlightedPicID: highlightedPicID) { pic in
                    selectedPics.contains(pic)
                } onSelect: { pic in
                    selectOrDeselectPic(pic)
                } selectedCount: {
                    selectedPics.count
                } onTogglePin: { pic in
                    togglePin(for: [pic])
                } onDelete: { pic in
                    deletePic(pic)
                } moveMenu: { pic in
                    PicMoveMenu(
                        title: "Shared.MoveTo",
                        systemImage: "tray.and.arrow.down",
                        pics: isSelectingPics ? selectedPics : [pic],
                        containingAlbum: currentAlbum,
                        totalAlbumCount: totalAlbumCount
                    ) {
                        refreshDataAfterPicMoved()
                    } onOtherLibraries: {
                        movePayload = .pics(isSelectingPics ? selectedPics : [pic])
                    }
                }
            } else if !hasFetchedPicCount {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(20.0)
            } else if picCount == 0 && !hideSectionHeaders {
                Text("Albums.NoPics", tableName: "Albums")
                    .foregroundStyle(.secondary)
                    .padding(20.0)
            }
        }
    }
}
