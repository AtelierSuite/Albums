import Engine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum DeepLinkRouter {

    static func albumDestination(from url: URL, currentLibraryID: String) -> IntentNavigator.Destination? {
        guard let albumID = url.pathComponents.dropFirst().first else { return nil }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let libraryID = queryItems.first { $0.name == "library" }?.value ?? currentLibraryID
        if let picID = queryItems.first(where: { $0.name == "pic" })?.value {
            let containingAlbumID = albumID == "__root__" ? nil : albumID
            return .pic(id: picID, albumID: containingAlbumID, libraryID: libraryID)
        }
        return .album(id: albumID, libraryID: libraryID)
    }

    static func sampleDataCounts(from url: URL) -> (pics: Int, albums: Int, legacyBlobs: Bool) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func count(_ name: String) -> Int? {
            components?.queryItems?.first { $0.name == name }?.value.flatMap { Int($0) }
        }
        return (count("pics") ?? Int.random(in: 11000...15000),
                count("albums") ?? Int.random(in: 20...60),
                (count("legacy") ?? 0) != 0)
    }

    static func open(_ destination: IntentNavigator.Destination,
                     navigation: NavigationManager,
                     libraryManager: LibraryManager) async {
        switch destination {
        case .library(let libraryID):
            guard let library = await LibrariesActor.shared.library(for: libraryID) else { return }
            showLibrary(library, navigation: navigation, libraryManager: libraryManager)
        case .album(let albumID, let libraryID):
            guard let library = await LibrariesActor.shared.library(for: libraryID),
                  let album = await DataActor.instance(for: libraryID).album(for: albumID) else { return }
            showLibrary(library, navigation: navigation, libraryManager: libraryManager)
            try? await Task.sleep(for: .milliseconds(250))
            navigation.push(.album(album: album), for: .collection)
        case .pic(let picID, let albumID, let libraryID):
            guard let library = await LibrariesActor.shared.library(for: libraryID) else { return }
            showLibrary(library, navigation: navigation, libraryManager: libraryManager)
            try? await Task.sleep(for: .milliseconds(250))
            await navigation.showInAlbum(picID: picID, albumID: albumID,
                                         libraryID: library.id, opensViewer: true)
        }
    }

    static func showLibrary(_ library: PicLibrary, navigation: NavigationManager, libraryManager: LibraryManager) {
        if library.id != libraryManager.currentLibrary.id || libraryManager.isPhotosModeEnabled {
            libraryManager.switchLibrary(to: library)
            navigation.signalDataChanged()
        }
        navigation.popAll()
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigation.collectionTabPath = [.library(id: library.id)]
        }
    }

    static func migratePreferencesFromUserDefaults() async {
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        guard let defaults else { return }

        let hasAlbumSort = defaults.object(forKey: "AlbumSort") != nil
        let hasPicSort = defaults.object(forKey: "PicSortType") != nil
        let hasAlbumStyle = defaults.object(forKey: "AlbumViewStyle") != nil
        let hasAlbumColumnCount = defaults.object(forKey: "AlbumColumnCount") != nil
        let hasPicColumnCount = defaults.object(forKey: "PicColumnCount") != nil
        let hasHideSectionHeaders = defaults.object(forKey: "HideSectionHeaders") != nil

        guard hasAlbumSort || hasPicSort || hasAlbumStyle
                || hasAlbumColumnCount || hasPicColumnCount
                || hasHideSectionHeaders else {
            return
        }

        let albumSort = defaults.string(forKey: "AlbumSort") ?? AlbumPreferences.defaults.albumSort
        let albumViewStyle = defaults.string(forKey: "AlbumViewStyle") ?? AlbumPreferences.defaults.albumViewStyle
        let albumColumnCount = hasAlbumColumnCount
            ? defaults.integer(forKey: "AlbumColumnCount")
            : AlbumPreferences.defaults.albumColumnCount
        let picSort = defaults.string(forKey: "PicSortType") ?? AlbumPreferences.defaults.picSort
        let picColumnCount = hasPicColumnCount
            ? defaults.integer(forKey: "PicColumnCount")
            : AlbumPreferences.defaults.picColumnCount
        let hideSectionHeaders = hasHideSectionHeaders
            ? defaults.bool(forKey: "HideSectionHeaders")
            : AlbumPreferences.defaults.hideSectionHeaders

        var albumIDs = await DataActor.shared.allAlbumIDs()
        albumIDs.insert("__root__", at: 0)
        for albumID in albumIDs {
            let prefs = AlbumPreferences(
                albumID: albumID,
                albumSort: albumSort,
                albumViewStyle: albumViewStyle,
                albumColumnCount: albumColumnCount,
                picSort: picSort,
                picColumnCount: picColumnCount,
                hideSectionHeaders: hideSectionHeaders
            )
            await DataActor.shared.insertPreferencesForMigration(prefs)
        }

        defaults.removeObject(forKey: "AlbumSort")
        defaults.removeObject(forKey: "PicSortType")
        defaults.removeObject(forKey: "AlbumViewStyle")
        defaults.removeObject(forKey: "AlbumColumnCount")
        defaults.removeObject(forKey: "PicColumnCount")
        defaults.removeObject(forKey: "HideSectionHeaders")
    }
}
