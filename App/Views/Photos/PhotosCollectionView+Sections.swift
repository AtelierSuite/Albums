import Engine
import Photos
import SwiftUI

// MARK: - Sections

extension PhotosCollectionView {
    var collectionContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0.0) {
                photosAlbumsSection
                if searchText.isEmpty {
                    Spacer()
                        .frame(height: 20.0)
                    photosPicsSection
                }
            }
            .padding([.top], 20.0)
        }
        .onAppear {
            if !hasFetchedCollections {
                items = photosManager.fetchTopLevelCollections().sortedAlbums(by: albumSort)
                hasFetchedCollections = true
            }
        }
        .task {
            if !hasFetchedRootAssets && !isFetchingRootAssets {
                isFetchingRootAssets = true
                rootAssets = oriented(await photosManager.fetchAssetsNotInAnyAlbum())
                hasFetchedRootAssets = true
                isFetchingRootAssets = false
            }
        }
    }

    var photosAlbumsSection: some View {
        Group {
            Group {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: filteredItems.count)
                } else {
                    SectionHeader(title: String(localized: "Albums.Albums", table: "Albums"),
                                  count: filteredItems.count) {
                        AlbumViewStylePicker(selection: $albumStyle)
                        AlbumSortPicker(selection: $albumSort)
                    }
                }
            }
            .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
            if !filteredItems.isEmpty {
                PhotosAlbumsSection(items: filteredItems, style: albumStyle,
                                    columnCount: albumColumnCount,
                                    onColumnCountChange: { albumColumnCount = $0 },
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
            } else if hasFetchedCollections {
                if searchText.isEmpty {
                    Text("Albums.NoAlbums", tableName: "Albums")
                        .foregroundStyle(.secondary)
                        .padding(20.0)
                }
            }
        }
    }

    var photosPicsSection: some View {
        Group {
            if !hasFetchedRootAssets {
                PhotosPicsSectionHeader(count: 0)
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(20.0)
            } else if !rootAssets.isEmpty {
                PhotosPicsSectionHeader(count: rootAssets.count)
                PhotosAssetsGrid(namespace: namespace, assets: rootAssets)
            }
        }
    }

    // MARK: - Access Denied

    var photosAccessDeniedView: some View {
        VStack(spacing: 16.0) {
            Image(systemName: "photo.badge.exclamationmark")
                .resizable()
                .scaledToFit()
                .frame(width: 64.0, height: 64.0)
                .foregroundStyle(.secondary)
            Text("Import.PhotosAccessDenied", tableName: "Import")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "Import.OpenSettings", table: "Import")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(40.0)
    }
}
