import Engine
import Photos
import SwiftUI

extension PhotosFolderImportPickerView {

    var folderListView: some View {
        List {
            if items.isEmpty && hasFetched {
                ContentUnavailableView(
                    String(localized: "Import.Folder.Empty", table: "Import"),
                    systemImage: "folder"
                )
            } else {
                ForEach(items) { item in
                    switch item {
                    case .album(let collection):
                        albumRow(for: collection)
                    case .folder(let folder):
                        folderRow(for: folder)
                    }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if let folder {
                VStack(alignment: .center, spacing: 16.0) {
                    Button {
                        startFolderImport(folder)
                    } label: {
                        Text("Import.ImportFolder", tableName: "Import")
                            .bold()
                            .padding(4.0)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.accent)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .padding(20.0)
            }
        }
        .onAppear {
            if !hasFetched {
                fetchFolders()
            }
        }
    }

    @ViewBuilder
    func folderRow(for folder: PHCollectionList) -> some View {
        NavigationLink(value: PHCollectionListWrapper(collectionList: folder)) {
            HStack(spacing: 12.0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                VStack(alignment: .leading, spacing: 2.0) {
                    Text(folder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
                    Text("Import.FolderContents.\(albumCount(in: folder)).\(totalImageCount(in: folder))",
                         tableName: "Import")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    func albumRow(for collection: PHAssetCollection) -> some View {
        HStack(spacing: 12.0) {
            albumThumbnail(for: collection)
            VStack(alignment: .leading, spacing: 2.0) {
                Text(collection.localizedTitle
                     ?? String(localized: "Import.Albums.Untitled", table: "Import"))
                Text(mediaCountText(in: collection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func albumThumbnail(for collection: PHAssetCollection) -> some View {
        if let firstAsset = firstAsset(in: collection) {
            PhotoThumbnailView(asset: firstAsset, size: CGSize(width: 56, height: 56))
                .frame(width: 32, height: 32)
                .clipShape(.rect(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
