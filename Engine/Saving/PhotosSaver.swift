import Photos
import UIKit

public enum PhotosCollection: Identifiable, Hashable {
    case album(PHAssetCollection)
    case folder(PHCollectionList)

    public var id: String {
        switch self {
        case .album(let album): album.localIdentifier
        case .folder(let folder): folder.localIdentifier
        }
    }

    public var title: String {
        switch self {
        case .album(let album): album.localizedTitle ?? ""
        case .folder(let folder): folder.localizedTitle ?? ""
        }
    }
}

public enum PhotosSaver {

    public struct MissingAlbums: Error {}
    public struct NoAccess: Error {}

    // A reused extension process can keep reporting .notDetermined after access was granted in
    // the app or another extension; requesting again returns the real status without a prompt.
    @discardableResult
    public static func authorize() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized || status == .limited
    }

    public static func collections(in folder: PHCollectionList? = nil) -> [PhotosCollection] {
        let result: PHFetchResult<PHCollection>
        if let folder {
            result = PHCollection.fetchCollections(in: folder, options: nil)
        } else {
            result = PHCollection.fetchTopLevelUserCollections(with: nil)
        }
        var collections: [PhotosCollection] = []
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                collections.append(.album(album))
            } else if let folder = collection as? PHCollectionList {
                collections.append(.folder(folder))
            }
        }
        return collections.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func albums(matching searchText: String) -> [PhotosCollection] {
        var albums: [PhotosCollection] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { album, _, _ in
                if (album.localizedTitle ?? "").localizedCaseInsensitiveContains(searchText) {
                    albums.append(.album(album))
                }
            }
        return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func createAlbum(named title: String, in folder: PHCollectionList?) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if let folder, let folderRequest = PHCollectionListChangeRequest(for: folder) {
                folderRequest.addChildCollections([request.placeholderForCreatedAssetCollection] as NSArray)
            }
        }
    }

    public static func save(_ items: [SharedItem], toCollectionsWithIDs collectionIDs: [String]) async throws {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: collectionIDs, options: nil)
        guard collections.count == collectionIDs.count else { throw MissingAlbums() }
        try await PHPhotoLibrary.shared().performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for item in items {
                let request = PHAssetCreationRequest.forAsset()
                switch item {
                case .image(let data):
                    request.addResource(with: .photo, data: data, options: nil)
                case .video(let url):
                    request.addResource(with: .video, fileURL: url, options: nil)
                }
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                }
            }
            collections.enumerateObjects { collection, _, _ in
                PHAssetCollectionChangeRequest(for: collection)?.addAssets(placeholders as NSArray)
            }
        }
    }

    public static func thumbnailData(forAssetWithIdentifier identifier: String, length: CGFloat) async -> Data? {
        await thumbnail(forAssetWithIdentifier: identifier, length: length)?.jpegData(compressionQuality: 0.8)
    }

    public static func coverAssetIdentifier(for collection: PhotosCollection) -> String? {
        guard case .album(let album) = collection else { return nil }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: album, options: options).firstObject?.localIdentifier
    }

    public static func thumbnail(forAssetWithIdentifier identifier: String, length: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: length, height: length),
                contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
