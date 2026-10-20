import Engine
import SwiftUI

extension AlbumView {
    var albumSection: some View {
        Group {
            if !hideSectionHeaders {
                Group {
#if targetEnvironment(macCatalyst)
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: displayedAlbums.count)
#else
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                      count: displayedAlbums.count)
                    } else {
                        SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                      count: displayedAlbums.count) {
                            Picker(String(localized: "Albums.Style", table: "Albums"),
                                   selection: ($albumStyleState.animation(.smooth.speed(2.0)))) {
                                Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                                      systemImage: "square.grid.2x2")
                                    .tag(ViewStyle.grid)
                                Label(String(localized: "Albums.Style.List", table: "Albums"),
                                      systemImage: "list.bullet")
                                    .tag(ViewStyle.list)
                                Label(String(localized: "Albums.Style.Carousel", table: "Albums"),
                                      systemImage: "rectangle.on.rectangle")
                                    .tag(ViewStyle.carousel)
                            }
                            Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $albumSortState) {
                                Text("Shared.Sort.Name.Ascending")
                                    .tag(SortType.nameAscending)
                                Text("Shared.Sort.Name.Descending")
                                    .tag(SortType.nameDescending)
                                Text("Shared.Sort.PicCount.Ascending")
                                    .tag(SortType.sizeAscending)
                                Text("Shared.Sort.PicCount.Descending")
                                    .tag(SortType.sizeDescending)
                            }
                            .pickerStyle(.menu)
                            if albumStyleState == .grid {
                                GridSizePicker(selection: $albumColumnCount, sizes: [2, 3, 4, 5], kind: .album)
                            }
                        }
                    }
#endif
                }
                .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !displayedAlbums.isEmpty {
                AlbumsSection(albums: displayedAlbums, style: $albumStyleState,
                             columnCount: albumColumnCount,
                             hideSectionHeaders: hideSectionHeaders,
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
            } else if searchText.isEmpty && !hideSectionHeaders {
                Text("Albums.NoAlbums", tableName: "Albums")
                    .foregroundStyle(.secondary)
                    .padding(20.0)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $picSortType) {
                                Text("Shared.Sort.DateAdded.Ascending")
                                    .tag(PicSortType.dateAddedAscending)
                                Text("Shared.Sort.DateAdded.Descending")
                                    .tag(PicSortType.dateAddedDescending)
                                Text("Shared.Sort.Name.Ascending")
                                    .tag(PicSortType.nameAscending)
                                Text("Shared.Sort.Name.Descending")
                                    .tag(PicSortType.nameDescending)
                                Text("Shared.Sort.ProminentColor")
                                    .tag(PicSortType.prominentColor)
                            }
                            .pickerStyle(.menu)
                            Picker(String(localized: "Albums.Style", table: "Albums"),
                                   systemImage: "paintbrush",
                                   selection: $picViewStyle.animation(.smooth.speed(2.0))) {
                                Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                                      systemImage: "square.grid.2x2")
                                    .tag(ViewStyle.grid)
                                Label(String(localized: "Albums.Style.Masonry", table: "Albums"),
                                      systemImage: "rectangle.3.offgrid")
                                    .tag(ViewStyle.masonry)
                            }
                            .pickerStyle(.menu)
                            GridSizePicker(selection: $columnCount, sizes: [2, 3, 4, 5, 8], kind: .pics)
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
                         style: picViewStyle,
                         highlightedPicID: highlightedPicID) { pic in
                    selectedPics.contains(pic)
                } onSelect: { pic in
                    selectOrDeselectPic(pic)
                } selectedCount: {
                    selectedPics.count
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
