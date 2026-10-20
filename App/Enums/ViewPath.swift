import Engine
import Foundation
import Photos
import UIKit
import SwiftUI

enum ViewPath: Hashable {
    case collection
    case albums
    case pics
    case picViewer(namespace: Namespace.ID)
    case album(album: Album)
    case more
    case moreDebug
    case moreTroubleshooting
    case moreAttributions
    case moreLabsFileExplorer
    case moreLabsTestData
    case photosFolder(folder: PHCollectionListWrapper)
    case photosAlbum(album: PHAssetCollectionWrapper)
    case photosAssetViewer(asset: PHAssetWrapper, namespace: Namespace.ID)
    case picViewerRestore
    case photosAssetViewerRestore
    case library(id: String)
    case photosLibrary
    case recentlyDeleted

    var isLibraryRoot: Bool {
        switch self {
        case .library, .photosLibrary: true
        default: false
        }
    }
}
