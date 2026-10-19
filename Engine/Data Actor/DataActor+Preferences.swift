import Foundation
@preconcurrency import SQLite

extension DataActor {

    public func preferences(forAlbumWithID albumID: String) -> AlbumPreferences {
        let query = preferencesTable.filter(prefAlbumId == albumID)
        guard let row = try? database.pluck(query) else {
            return AlbumPreferences.defaults
        }
        return AlbumPreferences(
            albumID: (try? row.get(prefAlbumId)) ?? albumID,
            albumSort: (try? row.get(prefAlbumSort)) ?? AlbumPreferences.defaults.albumSort,
            albumViewStyle: (try? row.get(prefAlbumViewStyle)) ?? AlbumPreferences.defaults.albumViewStyle,
            albumColumnCount: (try? row.get(prefAlbumColumnCount)) ?? AlbumPreferences.defaults.albumColumnCount,
            picSort: (try? row.get(prefPicSort)) ?? AlbumPreferences.defaults.picSort,
            picColumnCount: (try? row.get(prefPicColumnCount)) ?? AlbumPreferences.defaults.picColumnCount,
            hideSectionHeaders: (try? row.get(prefHideSectionHeaders)) ?? AlbumPreferences.defaults.hideSectionHeaders
        )
    }

    public func savePreferences(_ prefs: AlbumPreferences) {
        let query = preferencesTable.filter(prefAlbumId == prefs.albumID)
        if (try? database.pluck(query)) != nil {
            _ = try? database.run(query.update(
                prefAlbumSort <- prefs.albumSort,
                prefAlbumViewStyle <- prefs.albumViewStyle,
                prefAlbumColumnCount <- prefs.albumColumnCount,
                prefPicSort <- prefs.picSort,
                prefPicColumnCount <- prefs.picColumnCount,
                prefHideSectionHeaders <- prefs.hideSectionHeaders
            ))
        } else {
            _ = try? database.run(preferencesTable.insert(
                prefAlbumId <- prefs.albumID,
                prefAlbumSort <- prefs.albumSort,
                prefAlbumViewStyle <- prefs.albumViewStyle,
                prefAlbumColumnCount <- prefs.albumColumnCount,
                prefPicSort <- prefs.picSort,
                prefPicColumnCount <- prefs.picColumnCount,
                prefHideSectionHeaders <- prefs.hideSectionHeaders
            ))
        }
    }

    public func deletePreferences(forAlbumWithID albumID: String) {
        let query = preferencesTable.filter(prefAlbumId == albumID)
        _ = try? database.run(query.delete())
    }

    public func allAlbumIDs() -> [String] {
        let query = albumsTable.select(albumId)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(albumId) }
    }

    public func insertPreferencesForMigration(_ prefs: AlbumPreferences) {
        _ = try? database.run(preferencesTable.insert(or: .ignore,
            prefAlbumId <- prefs.albumID,
            prefAlbumSort <- prefs.albumSort,
            prefAlbumViewStyle <- prefs.albumViewStyle,
            prefAlbumColumnCount <- prefs.albumColumnCount,
            prefPicSort <- prefs.picSort,
            prefPicColumnCount <- prefs.picColumnCount,
            prefHideSectionHeaders <- prefs.hideSectionHeaders
        ))
    }
}
