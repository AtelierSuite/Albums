import Engine
import Photos
import SwiftUI

extension PhotosFolderImportPickerView {

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    func fetchFolders() {
        var collected: [PHCollectionItem] = []

        if let folder {
            let result = PHCollection.fetchCollections(in: folder, options: nil)
            result.enumerateObjects { collection, _, _ in
                if let subfolder = collection as? PHCollectionList {
                    collected.append(.folder(subfolder))
                } else if let album = collection as? PHAssetCollection {
                    collected.append(.album(album))
                }
            }
        } else {
            let topLevelResult = PHCollectionList.fetchTopLevelUserCollections(with: nil)
            topLevelResult.enumerateObjects { collection, _, _ in
                if let subfolder = collection as? PHCollectionList {
                    collected.append(.folder(subfolder))
                } else if let album = collection as? PHAssetCollection {
                    collected.append(.album(album))
                }
            }
        }

        items = collected.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        hasFetched = true
    }

    func albumCount(in folder: PHCollectionList) -> Int {
        var count = 0
        let result = PHCollection.fetchCollections(in: folder, options: nil)
        result.enumerateObjects { collection, _, _ in
            if collection is PHAssetCollection {
                count += 1
            }
        }
        return count
    }

    func totalImageCount(in folder: PHCollectionList) -> Int {
        countImagesRecursively(in: folder)
    }

    func countImagesRecursively(in folder: PHCollectionList) -> Int {
        var count = 0
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let result = PHCollection.fetchCollections(in: folder, options: nil)
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                count += PHAsset.fetchAssets(in: album, options: fetchOptions).count
            } else if let subfolder = collection as? PHCollectionList {
                count += countImagesRecursively(in: subfolder)
            }
        }
        return count
    }

    func mediaCountText(in collection: PHAssetCollection) -> String {
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

    func firstAsset(in collection: PHAssetCollection) -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: fetchOptions).firstObject
    }
}
