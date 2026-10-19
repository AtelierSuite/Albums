import Engine
import Foundation
import Photos

@MainActor
@Observable
class PhotosManager {

    var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
    }

    // MARK: - Fetch Top-Level Collections

    func fetchTopLevelCollections() -> [PHCollectionItem] {
        var collected: [PHCollectionItem] = []
        let result = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                collected.append(.album(album))
            } else if let folder = collection as? PHCollectionList {
                collected.append(.folder(folder))
            }
        }
        return collected.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Fetch Collections in Folder

    func fetchCollections(in folder: PHCollectionList) -> [PHCollectionItem] {
        var collected: [PHCollectionItem] = []
        let result = PHCollection.fetchCollections(in: folder, options: nil)
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                collected.append(.album(album))
            } else if let subfolder = collection as? PHCollectionList {
                collected.append(.folder(subfolder))
            }
        }
        return collected.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Fetch Assets in Album

    func fetchAssets(in collection: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: fetchOptions)
    }

    func mediaCount(in collection: PHAssetCollection) -> Int {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        return PHAsset.fetchAssets(in: collection, options: fetchOptions).count
    }

    func firstAsset(in collection: PHAssetCollection) -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: fetchOptions).firstObject
    }

    // MARK: - Fetch Assets Not in Any Album

    func fetchAssetsNotInAnyAlbum() async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let allOptions = PHFetchOptions()
            allOptions.predicate = NSPredicate(
                format: "mediaType = %d OR mediaType = %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allAssets = PHAsset.fetchAssets(with: allOptions)

            var albumedIdentifiers: Set<String> = []
            albumedIdentifiers.reserveCapacity(allAssets.count)
            let albums = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil
            )
            albums.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(
                    format: "mediaType = %d OR mediaType = %d",
                    PHAssetMediaType.image.rawValue,
                    PHAssetMediaType.video.rawValue
                )
                let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                assets.enumerateObjects { asset, _, _ in
                    albumedIdentifiers.insert(asset.localIdentifier)
                }
            }

            var result: [PHAsset] = []
            result.reserveCapacity(max(0, allAssets.count - albumedIdentifiers.count))
            allAssets.enumerateObjects { asset, _, _ in
                if !albumedIdentifiers.contains(asset.localIdentifier) {
                    result.append(asset)
                }
            }
            return result
        }.value
    }

    // MARK: - Nested Albums (Experimental)

    /// In nested albums mode, within a folder:
    /// - If an album named "▶︎ <FolderName>" exists, its photos become the folder's own pics
    /// - The remaining albums become nested sub-albums
    /// Returns (ownPicsAlbum, childAlbums, childFolders)
    func resolveNestedAlbums(
        in folder: PHCollectionList
    ) -> ResolvedNestedAlbums {
        let folderName = folder.localizedTitle ?? ""
        let markerName = "▶︎ \(folderName)"
        var ownPicsCollection: PHAssetCollection?
        var albums: [PHAssetCollection] = []
        var folders: [PHCollectionList] = []

        let result = PHCollection.fetchCollections(in: folder, options: nil)
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                if album.localizedTitle == markerName {
                    ownPicsCollection = album
                } else {
                    albums.append(album)
                }
            } else if let subfolder = collection as? PHCollectionList {
                folders.append(subfolder)
            }
        }

        albums.sort {
            ($0.localizedTitle ?? "").localizedCaseInsensitiveCompare($1.localizedTitle ?? "") == .orderedAscending
        }
        folders.sort {
            ($0.localizedTitle ?? "").localizedCaseInsensitiveCompare($1.localizedTitle ?? "") == .orderedAscending
        }

        return ResolvedNestedAlbums(ownPicsCollection: ownPicsCollection, albums: albums, folders: folders)
    }

    // MARK: - Album Management

    nonisolated func createAlbum(named title: String) async throws -> PHAssetCollection {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let localIdentifier = placeholder?.localIdentifier,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [localIdentifier], options: nil
              ).firstObject else {
            throw PhotosManagerError.albumCreationFailed
        }
        return collection
    }

    nonisolated func renameAlbum(_ collection: PHAssetCollection, to newTitle: String) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.title = newTitle
        }
    }

    nonisolated func deleteAlbum(_ collection: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSFastEnumeration)
        }
    }

    nonisolated func moveAlbum(_ collection: PHAssetCollection, into folder: PHCollectionList) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let folderRequest = PHCollectionListChangeRequest(for: folder) else { return }
            folderRequest.addChildCollections([collection] as NSFastEnumeration)
        }
    }

    nonisolated func createFolder(named title: String) async throws -> PHCollectionList {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: title)
            placeholder = request.placeholderForCreatedCollectionList
        }
        guard let localIdentifier = placeholder?.localIdentifier,
              let folder = PHCollectionList.fetchCollectionLists(
                  withLocalIdentifiers: [localIdentifier], options: nil
              ).firstObject else {
            throw PhotosManagerError.folderCreationFailed
        }
        return folder
    }

    nonisolated func deleteFolder(_ folder: PHCollectionList) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHCollectionListChangeRequest.deleteCollectionLists([folder] as NSFastEnumeration)
        }
    }

    nonisolated func addAssets(_ assets: [PHAsset], to collection: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets(assets as NSFastEnumeration)
        }
    }

    func searchAlbums(matching searchText: String) -> [PHCollectionItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title CONTAINS[cd] %@", searchText)
        var results: [PHCollectionItem] = []
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        albums.enumerateObjects { collection, _, _ in
            results.append(.album(collection))
        }
        return results.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

enum PhotosManagerError: LocalizedError {
    case albumCreationFailed
    case folderCreationFailed

    var errorDescription: String? {
        switch self {
        case .albumCreationFailed: return String(localized: "Photos.Error.AlbumCreationFailed", table: "Photos")
        case .folderCreationFailed: return String(localized: "Photos.Error.FolderCreationFailed", table: "Photos")
        }
    }
}
