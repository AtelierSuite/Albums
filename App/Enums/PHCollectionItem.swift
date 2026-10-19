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
}
