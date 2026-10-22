import Engine
import Foundation
import Photos

enum PHCollectionItem: Identifiable {
    case album(PHAssetCollection)
    case folder(PHCollectionList)

    var id: String {
        switch self {
        case .album(let collection): collection.localIdentifier
        case .folder(let list): list.localIdentifier
        }
    }

    var title: String {
        switch self {
        case .album(let collection): collection.localizedTitle ?? ""
        case .folder(let list): list.localizedTitle ?? ""
        }
    }

    var picCount: Int {
        switch self {
        case .album(let collection):
            let estimated = collection.estimatedAssetCount
            if estimated != NSNotFound {
                return estimated
            }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType = %d OR mediaType = %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            return PHAsset.fetchAssets(in: collection, options: options).count
        case .folder:
            return 0
        }
    }

    var albumCount: Int {
        switch self {
        case .album:
            return 0
        case .folder(let list):
            return PHCollection.fetchCollections(in: list, options: nil).count
        }
    }
}

extension Array where Element == PHCollectionItem {
    func sortedAlbums(by sortType: SortType) -> [PHCollectionItem] {
        switch sortType {
        case .nameAscending:
            return sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDescending:
            return sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .sizeAscending:
            return map { ($0, $0.picCount + $0.albumCount) }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        case .sizeDescending:
            return map { ($0, $0.picCount + $0.albumCount) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
    }
}
