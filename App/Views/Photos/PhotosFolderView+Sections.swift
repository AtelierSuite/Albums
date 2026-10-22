import Engine
import Photos
import SwiftUI

// MARK: - Sections

extension PhotosFolderView {
    var albumsSection: some View {
        Group {
            Group {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: filteredItems.count)
                } else {
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: filteredItems.count) {
                        Picker(String(localized: "Albums.Style", table: "Albums"),
                               selection: $albumStyleState.animation(.smooth.speed(2))) {
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
                        if albumStyleState == .grid {
                            GridSizePicker(selection: $albumColumnCount, sizes: [2, 3, 4])
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
            PhotosAlbumsSection(items: filteredItems, style: $albumStyleState,
                                onRename: { collection in
                                    albumToRename = collection
                                },
                                onDelete: { collection in
                                    albumToDelete = collection
                                    isConfirmingDeleteAlbum = true
                                },
                                onMoveToFolder: { collection in
                                    albumToMove = collection
                                },
                                onDeleteFolder: { folder in
                                    folderToDelete = folder
                                    isConfirmingDeleteFolder = true
                                },
                                onDropAssets: { transferable, collection in
                                    addDroppedAsset(transferable, to: collection)
                                },
                                coverRefreshID: coverRefreshID)
        }
    }

    func picsSection(fetchResult: PHFetchResult<PHAsset>) -> some View {
        Group {
            SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"), count: fetchResult.count)
                .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
            PhotosFetchResultAssetsGrid(namespace: namespace, fetchResult: fetchResult)
        }
    }
}
