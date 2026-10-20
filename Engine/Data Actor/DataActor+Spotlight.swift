import Foundation
@preconcurrency import SQLite

public struct SpotlightAlbumRow: Sendable {
    public let id: String
    public let name: String
    public let parentAlbumID: String?
    public let dateCreated: Date
    public let coverSize: Int
}

public struct SpotlightPicRow: Sendable {
    public let id: String
    public let name: String
    public let albumID: String?
    public let dateAdded: Date
    public let mediaType: MediaType
    public let duration: Double?
    public let thumbnailSize: Int
}

extension DataActor {

    public func spotlightAlbumRows() -> [SpotlightAlbumRow] {
        let statement = "SELECT id, name, parent_album_id, date_created, IFNULL(length(cover_photo), 0) FROM albums"
        guard let rows = try? database.safeRows(statement) else { return [] }
        return rows.compactMap { row in
            guard row.count == 5, let id = row[0] as? String else { return nil }
            return SpotlightAlbumRow(
                id: id,
                name: row[1] as? String ?? "",
                parentAlbumID: row[2] as? String,
                dateCreated: Date(timeIntervalSince1970: Self.spotlightDouble(row[3]) ?? 0),
                coverSize: Int(row[4] as? Int64 ?? 0)
            )
        }
    }

    public func spotlightPicRows() -> [SpotlightPicRow] {
        let statement = """
            SELECT id, name, containing_album_id, date_added, media_type, duration,
                   IFNULL(length(thumbnail_data), 0) FROM pics
            """
        guard let rows = try? database.safeRows(statement) else { return [] }
        return rows.compactMap { row in
            guard row.count == 7, let id = row[0] as? String else { return nil }
            return SpotlightPicRow(
                id: id,
                name: row[1] as? String ?? "",
                albumID: row[2] as? String,
                dateAdded: Date(timeIntervalSince1970: Self.spotlightDouble(row[3]) ?? 0),
                mediaType: MediaType(rawValue: Int(row[4] as? Int64 ?? 0)) ?? .pic,
                duration: Self.spotlightDouble(row[5]),
                thumbnailSize: Int(row[6] as? Int64 ?? 0)
            )
        }
    }

    public func spotlightThumbnails(forPicIDs ids: [String]) -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let query = picsTable
            .filter(ids.contains(picId))
            .select(picId, picThumbnailData)
        guard let rows = try? database.safeRows(query) else { return [:] }
        var result: [String: Data] = [:]
        for row in rows {
            if let id = try? row.get(picId), let data = try? row.get(picThumbnailData) {
                result[id] = data
            }
        }
        return result
    }

    private static func spotlightDouble(_ value: SQLite.Binding?) -> Double? {
        switch value {
        case let double as Double: double
        case let integer as Int64: Double(integer)
        default: nil
        }
    }
}
