import Foundation
@preconcurrency import SQLite

public struct LibrarySearchResults: Sendable {
    public let albums: [Album]
    public let pics: [Pic]
    public let albumNames: [String: String]

    public var isEmpty: Bool { albums.isEmpty && pics.isEmpty }
}

extension DataActor {
    public func searchLibrary(
        matching searchText: String, albumLimit: Int = 50, picLimit: Int = 200
    ) throws -> LibrarySearchResults {
        let pattern = "%\(escapedLikePattern(searchText))%"
        var albumNames: [String: String] = [:]

        // swiftlint:disable line_length
        let albumSQL = """
            SELECT a.id, a.name, a.cover_photo IS NOT NULL, a.parent_album_id, a.date_created, parent.name
            FROM albums a LEFT JOIN albums parent ON parent.id = a.parent_album_id
            WHERE a.name LIKE ? ESCAPE '\\' ORDER BY a.name COLLATE NOCASE LIMIT ?
            """
        let picSQL = """
            SELECT p.id, p.name, p.containing_album_id, p.date_added, p.media_type, p.duration, p.file_path, a.name
            FROM (SELECT rowid AS rid FROM pics WHERE name LIKE ? ESCAPE '\\' AND date_deleted IS NULL ORDER BY name COLLATE NOCASE LIMIT ?) matches
            JOIN pics p ON p.rowid = matches.rid
            LEFT JOIN albums a ON a.id = p.containing_album_id
            ORDER BY p.name COLLATE NOCASE
            """
        // swiftlint:enable line_length

        let albums = try database.safeRows(albumSQL, [pattern, Int64(albumLimit)]).map { row -> Album in
            let parentID = row[3] as? String
            if let parentID, let parentName = row[5] as? String {
                albumNames[parentID] = parentName
            }
            return Album(id: row[0] as? String ?? "", name: row[1] as? String ?? "",
                         hasCoverPhoto: (row[2] as? Int64 ?? 0) != 0,
                         parentAlbumID: parentID,
                         dateCreated: Date(timeIntervalSince1970: row[4] as? Double ?? 0))
        }
        try Task.checkCancellation()
        populateCounts(for: albums)
        try Task.checkCancellation()

        let pics = try database.safeRows(picSQL, [pattern, Int64(picLimit)]).map { row -> Pic in
            let albumID = row[2] as? String
            if let albumID, let albumName = row[7] as? String {
                albumNames[albumID] = albumName
            }
            return Pic(id: row[0] as? String ?? "", name: row[1] as? String ?? "",
                       containingAlbumID: albumID,
                       dateAdded: Date(timeIntervalSince1970: row[3] as? Double ?? 0),
                       mediaType: MediaType(rawValue: Int(row[4] as? Int64 ?? 0)) ?? .pic,
                       duration: row[5] as? Double,
                       filePath: row[6] as? String)
        }
        return LibrarySearchResults(albums: albums, pics: pics, albumNames: albumNames)
    }

    private func escapedLikePattern(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
