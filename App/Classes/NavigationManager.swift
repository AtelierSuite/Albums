import Engine
import Foundation
import UIKit

struct PicRevealRequest: Equatable, Sendable {
    let id = UUID()
    let picID: String
    let albumID: String?
}

@MainActor
class NavigationManager: ObservableObject {

    @Published var collectionTabPath: [ViewPath] = []
    @Published var albumsTabPath: [ViewPath] = []
    @Published var picsTabPath: [ViewPath] = []
    @Published var settingsTabPath: [ViewPath] = []
    @Published var dataVersion: Int = 0
    @Published var picRevealRequest: PicRevealRequest?

    private let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
    private let lastLocationKey = "LastLibraryLocation"
    private let lastAlbumIDKey = "LastAlbumID"

    func popAll() {
        collectionTabPath = collectionTabPath.first.map { $0.isLibraryRoot ? [$0] : [] } ?? []
        albumsTabPath.removeAll()
        picsTabPath.removeAll()
        settingsTabPath.removeAll()
    }

    func signalDataDeleted() {
        popAll()
        dataVersion += 1
    }

    func signalDataChanged() {
        dataVersion += 1
    }

    func push(_ viewPath: ViewPath, for tab: TabType) {
        switch tab {
        case .collection:
            collectionTabPath.append(viewPath)
        case .albums:
            albumsTabPath.append(viewPath)
        case .pics:
            picsTabPath.append(viewPath)
        case .settings:
            settingsTabPath.append(viewPath)
        }
    }

    func showInAlbum(picID: String, albumID: String?, libraryID: String) async {
        var albumPath: [ViewPath] = []
        if let albumID {
            let albums = await DataActor.shared.albumPath(forAlbumWithID: albumID)
            albumPath = albums.map { .album(album: $0) }
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            collectionTabPath = [.library(id: libraryID)] + albumPath
        } else {
            collectionTabPath = albumPath
        }
        picRevealRequest = PicRevealRequest(picID: picID, albumID: albumID)
    }

    func saveLibraryLocation() {
        switch collectionTabPath.first {
        case .library: defaults?.set("library", forKey: lastLocationKey)
        case .photosLibrary: defaults?.set("photos", forKey: lastLocationKey)
        default: defaults?.set("root", forKey: lastLocationKey)
        }
        let lastAlbumID = collectionTabPath.reversed().lazy.compactMap { viewPath -> String? in
            if case .album(let album) = viewPath { return album.id }
            return nil
        }.first
        defaults?.set(lastAlbumID, forKey: lastAlbumIDKey)
    }

    func restoredLibraryPath(currentLibraryID: String, isPhotosModeEnabled: Bool) async -> [ViewPath] {
        let location = defaults?.string(forKey: lastLocationKey) ?? "library"
        switch location {
        case "root":
            return []
        case "photos" where isPhotosModeEnabled:
            return [.photosLibrary]
        default:
            guard !isPhotosModeEnabled else { return [.photosLibrary] }
            var path: [ViewPath] = [.library(id: currentLibraryID)]
            if let albumID = defaults?.string(forKey: lastAlbumIDKey) {
                let albums = await DataActor.shared.albumPath(forAlbumWithID: albumID)
                path.append(contentsOf: albums.map { .album(album: $0) })
            }
            return path
        }
    }
}
