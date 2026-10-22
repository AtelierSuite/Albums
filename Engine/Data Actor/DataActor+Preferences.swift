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
        if let stored = storedPreferences(forAlbumWithID: prefs.albumID), stored == prefs { return }
        upsertPreferences(prefs, extraSetters: [syncDirty <- true, syncLastModified <- syncTimestamp])
    }

    private func upsertPreferences(_ prefs: AlbumPreferences, extraSetters: [Setter]) {
        let setters: [Setter] = [
            prefAlbumSort <- prefs.albumSort,
            prefAlbumViewStyle <- prefs.albumViewStyle,
            prefAlbumColumnCount <- prefs.albumColumnCount,
            prefPicSort <- prefs.picSort,
            prefPicColumnCount <- prefs.picColumnCount,
            prefHideSectionHeaders <- prefs.hideSectionHeaders
        ] + extraSetters
        let query = preferencesTable.filter(prefAlbumId == prefs.albumID)
        if (try? database.pluck(query)) != nil {
            _ = try? database.run(query.update(setters))
        } else {
            _ = try? database.run(preferencesTable.insert([prefAlbumId <- prefs.albumID] + setters))
        }
    }

    public func deletePreferences(forAlbumWithID albumID: String) {
        deletePreferences(forAlbumIDs: [albumID])
    }

    public func deletePreferences(forAlbumIDs albumIDs: [String]) {
        guard !albumIDs.isEmpty else { return }
        let query = preferencesTable.filter(albumIDs.contains(prefAlbumId))
        let syncedQuery = query.filter(syncCKSystemFields != nil).select(prefAlbumId)
        let syncedAlbumIDs = (try? database.safeRows(syncedQuery).map { $0[prefAlbumId] }) ?? []
        recordTombstones(ids: syncedAlbumIDs.map(AlbumPreferences.recordName(forAlbumID:)),
                         recordType: SyncRecordType.albumPreferences)
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

    // MARK: - Sync

    public func dirtyPreferencesAlbumIDs() -> [String] {
        let query = preferencesTable.filter(syncDirty == true || syncCKSystemFields == nil).select(prefAlbumId)
        return (try? database.safeRows(query).map { $0[prefAlbumId] }) ?? []
    }

    public func allPreferencesAlbumIDs() -> [String] {
        (try? database.safeRows(preferencesTable.select(prefAlbumId)).map { $0[prefAlbumId] }) ?? []
    }

    public func preferencesSyncSnapshot(forAlbumID albumID: String) -> AlbumPreferencesSyncSnapshot? {
        guard let prefs = storedPreferences(forAlbumWithID: albumID),
              let row = try? database.pluck(preferencesTable.filter(prefAlbumId == albumID)) else { return nil }
        return AlbumPreferencesSyncSnapshot(preferences: prefs, systemFields: try? row.get(syncCKSystemFields))
    }

    public func applyRemotePreferences(_ snapshot: AlbumPreferencesSyncSnapshot) {
        upsertPreferences(snapshot.preferences, extraSetters: [
            syncDirty <- false,
            syncCKSystemFields <- snapshot.systemFields,
            syncLastModified <- syncTimestamp
        ])
    }

    public func markPreferencesSynced(albumID: String, systemFields: Data?) {
        _ = try? database.run(preferencesTable.filter(prefAlbumId == albumID)
            .update(syncDirty <- false, syncCKSystemFields <- systemFields))
    }

    public func removePreferencesForRemoteDelete(albumID: String) {
        _ = try? database.run(preferencesTable.filter(prefAlbumId == albumID).delete())
    }
}
