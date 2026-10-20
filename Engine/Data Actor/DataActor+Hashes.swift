import Foundation
@preconcurrency import SQLite

extension DataActor {

    public func allPicIDs() -> [String] {
        let query = picsTable.filter(picDateDeleted == nil).select(picId)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(picId) }
    }

    public func picAlbumIDs() -> [(picID: String, albumID: String?)] {
        let query = picsTable.filter(picDateDeleted == nil).select(picId, picAlbumId)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { row in
            guard let id = try? row.get(picId) else { return nil }
            return (id, (try? row.get(picAlbumId)) ?? nil)
        }
    }

    public func picIDs(inAlbumWithID albumID: String) -> [String] {
        let query = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil).select(picId)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(picId) }
    }

    public func picIDsNotInAnyAlbum() -> [String] {
        let query = picsTable.filter(picAlbumId == nil && picDateDeleted == nil).select(picId)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(picId) }
    }

    public func pic(forID picID: String) -> Pic? {
        let query = picsTable
            .filter(picId == picID)
            .select(picId, picName, picAlbumId, picDateAdded, picThumbnailData)
        guard let row = try? database.pluck(query) else { return nil }
        return picFrom(row: row)
    }
}
