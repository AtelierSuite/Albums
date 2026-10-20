import Foundation
@preconcurrency import SQLite

extension DataActor {

    public static let recentlyDeletedRetentionDays = 30

    public var picDateDeleted: SQLite.Expression<Double?> { SQLite.Expression<Double?>("date_deleted") }

    public func moveToRecentlyDeleted(picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let now = syncTimestamp
        let query = picsTable.filter(picIDs.contains(picId) && picDateDeleted == nil)
        _ = try? database.run(query.update(
            picDateDeleted <- now, syncDirty <- true, syncLastModified <- now
        ))
        notifyLocalMutation()
    }

    @discardableResult
    public func moveAlbumAndContentsToRecentlyDeleted(withID albumID: String) -> [String] {
        let subtree = collectSubtree(forAlbumID: albumID)
        moveToRecentlyDeleted(picIDs: subtree.picIDs)

        for id in subtree.albumIDs where albumWasSynced(id: id) {
            recordTombstone(id: id, recordType: SyncRecordType.album)
        }
        _ = try? database.run(albumsTable.filter(subtree.albumIDs.contains(albumId)).delete())
        _ = try? database.run(preferencesTable.filter(subtree.albumIDs.contains(prefAlbumId)).delete())
        notifyLocalMutation()
        return subtree.picIDs
    }

    public func recentlyDeletedPics() throws -> [Pic] {
        let query = picsTable
            .filter(picDateDeleted != nil)
            .select(picId, picName, picAlbumId, picDateAdded, picMediaType,
                    picDuration, picFilePath, picDateDeleted)
            .order(picDateDeleted.desc)
        return try database.safeRows(query).map { picFrom(row: $0) }
    }

    public func recentlyDeletedCount() -> Int {
        (try? database.scalar(picsTable.filter(picDateDeleted != nil).count)) ?? 0
    }

    public func restoreFromRecentlyDeleted(picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let now = syncTimestamp
        let query = picsTable.filter(picIDs.contains(picId) && picDateDeleted != nil)
        let albumIDs = Set(((try? database.safeRows(query.select(picAlbumId))) ?? [])
            .compactMap { (try? $0.get(picAlbumId)) ?? nil })
        let survivingAlbumIDs = Set(existingAlbumIDs(among: Array(albumIDs)))
        let orphanedAlbumIDs = Array(albumIDs.subtracting(survivingAlbumIDs))
        if !orphanedAlbumIDs.isEmpty {
            _ = try? database.run(query.filter(orphanedAlbumIDs.contains(picAlbumId)).update(
                picAlbumId <- nil
            ))
        }
        _ = try? database.run(query.update(
            picDateDeleted <- nil, syncDirty <- true, syncLastModified <- now
        ))
        notifyLocalMutation()
    }

    public func recentlyDeletedPicIDs(deletedBefore cutoff: Date) -> [String] {
        let query = picsTable
            .filter(picDateDeleted != nil && picDateDeleted < cutoff.timeIntervalSince1970)
            .select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func recentlyDeletedPicIDs(among ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let query = picsTable
            .filter(ids.contains(picId) && picDateDeleted != nil)
            .select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func allRecentlyDeletedPicIDs() -> [String] {
        let query = picsTable.filter(picDateDeleted != nil).select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }
}
