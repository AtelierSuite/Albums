import Engine
import Photos
import SwiftUI

struct PhotosAlbumPickerView: View {

    var folder: PHCollectionList?
    var selectedAlbum: Album?
    var onDismiss: () -> Void

    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var items: [PHCollectionItem] = []
    @State private var hasFetched: Bool = false

    var body: some View {
        Group {
            if folder != nil {
                albumListView
            } else {
                switch authorizationStatus {
                case .authorized, .limited:
                    albumListView
                case .denied, .restricted:
                    deniedView
                default:
                    ProgressView()
                        .task {
                            await requestAuthorization()
                        }
                }
            }
        }
        .navigationTitle(
            folder == nil
            ? String(localized: "Import.Albums", table: "Import")
            : (folder?.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PHAssetCollectionWrapper.self) { wrapper in
            PhotosAssetGridView(
                collection: wrapper.collection,
                selectedAlbum: selectedAlbum,
                onDismiss: onDismiss
            )
        }
        .navigationDestination(for: PHCollectionListWrapper.self) { wrapper in
            PhotosAlbumPickerView(
                folder: wrapper.collectionList,
                selectedAlbum: selectedAlbum,
                onDismiss: onDismiss
            )
        }
    }

    // MARK: - Album List

    private var albumListView: some View {
        List {
            if folder != nil && items.isEmpty && hasFetched {
                ContentUnavailableView(String(localized: "Import.Folder.Empty", table: "Import"), systemImage: "folder")
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
        .onAppear {
            if !hasFetched {
                fetchAlbums()
            }
        }
    }

    @ViewBuilder
    private func albumRow(for collection: PHAssetCollection) -> some View {
        NavigationLink(value: PHAssetCollectionWrapper(collection: collection)) {
            HStack(spacing: 12.0) {
                albumThumbnail(for: collection)
                VStack(alignment: .leading, spacing: 2.0) {
                    Text(collection.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
                    Text(mediaCountText(in: collection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    private func folderRow(for folder: PHCollectionList) -> some View {
        NavigationLink(value: PHCollectionListWrapper(collectionList: folder)) {
            HStack(spacing: 12.0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                Text(folder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
                Spacer()
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    private func albumThumbnail(for collection: PHAssetCollection) -> some View {
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

    // MARK: - Denied View

    private var deniedView: some View {
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

    // MARK: - Helpers

    private func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    private func fetchAlbums() {
        var collected: [PHCollectionItem] = []

        if let folder {
            let result = PHCollection.fetchCollections(in: folder, options: nil)
            result.enumerateObjects { collection, _, _ in
                if let album = collection as? PHAssetCollection {
                    collected.append(.album(album))
                } else if let subfolder = collection as? PHCollectionList {
                    collected.append(.folder(subfolder))
                }
            }
        } else {
            let topLevelResult = PHCollectionList.fetchTopLevelUserCollections(with: nil)
            topLevelResult.enumerateObjects { collection, _, _ in
                if let album = collection as? PHAssetCollection {
                    collected.append(.album(album))
                } else if let subfolder = collection as? PHCollectionList {
                    collected.append(.folder(subfolder))
                }
            }
        }

        items = collected.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        hasFetched = true
    }

    private func mediaCountText(in collection: PHAssetCollection) -> String {
        let photoOptions = PHFetchOptions()
        photoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let photoCount = PHAsset.fetchAssets(in: collection, options: photoOptions).count

        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        let videoCount = PHAsset.fetchAssets(in: collection, options: videoOptions).count

        var parts: [String] = []
        if photoCount > 0 {
            parts.append(String(localized: "Import.Count.Photos.\(photoCount)", table: "Import"))
        }
        if videoCount > 0 {
            parts.append(String(localized: "Import.Count.Videos.\(videoCount)", table: "Import"))
        }
        return parts.isEmpty ? "0" : parts.joined(separator: ", ")
    }

    private func firstAsset(in collection: PHAssetCollection) -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: fetchOptions).firstObject
    }
}
