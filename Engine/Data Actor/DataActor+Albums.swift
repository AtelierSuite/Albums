import Foundation
@preconcurrency import SQLite

extension DataActor {
    public func albumsWithCounts(sortedBy sortType: SortType) throws -> [Album] {
        let rows = try database.safeRows(albumsTable)
        let albums = rows.map { row -> Album in
            albumFrom(row: row, loadChildren: false)
        }
        populateCounts(for: albums)
        return sortAlbum(albums, sortedBy: sortType)
    }

    public func albumsWithCounts(in album: Album?, sortedBy sortType: SortType) throws -> [Album] {
        let sql: String
        let bindings: [Binding?]
        if let albumID = album?.id {
            // swiftlint:disable:next line_length
            sql = "SELECT id, name, cover_photo IS NOT NULL, parent_album_id, date_created FROM albums WHERE parent_album_id = ?"
            bindings = [albumID as Binding?]
        } else {
            // swiftlint:disable:next line_length
            sql = "SELECT id, name, cover_photo IS NOT NULL, parent_album_id, date_created FROM albums WHERE parent_album_id IS NULL"
            bindings = []
        }
        let stmt = try database.safeRows(sql, bindings)
        let albums = stmt.map { row -> Album in
            let id = row[0] as? String ?? ""
            let name = row[1] as? String ?? ""
            let hasCover = (row[2] as? Int64 ?? 0) != 0
            let parentId = row[3] as? String
            let dateCreated = Date(timeIntervalSince1970: row[4] as? Double ?? 0)
            return Album(id: id, name: name, hasCoverPhoto: hasCover,
                         parentAlbumID: parentId, dateCreated: dateCreated)
        }
        populateCounts(for: albums)
        return sortAlbum(albums, sortedBy: sortType)
    }

    func populateCounts(for albums: [Album]) {
        let ids = albums.map { $0.id }
        guard !ids.isEmpty else { return }

        let bindings: [Binding?] = ids.map { $0 as Binding? }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")

        var albumCounts: [String: Int] = [:]
        // swiftlint:disable:next line_length
        let albumCountSQL = "SELECT parent_album_id, COUNT(*) FROM albums WHERE parent_album_id IN (\(placeholders)) GROUP BY parent_album_id"
        if let stmt = try? database.safeRows(albumCountSQL, bindings) {
            for row in stmt {
                if let parentId = row[0] as? String,
                   let count = row[1] as? Int64 {
                    albumCounts[parentId] = Int(count)
                }
            }
        }

        var picCounts: [String: Int] = [:]
        // swiftlint:disable:next line_length
        let picCountSQL = "SELECT containing_album_id, COUNT(*) FROM pics WHERE containing_album_id IN (\(placeholders)) AND date_deleted IS NULL GROUP BY containing_album_id"
        if let stmt = try? database.safeRows(picCountSQL, bindings) {
            for row in stmt {
                if let albumId = row[0] as? String,
                   let count = row[1] as? Int64 {
                    picCounts[albumId] = Int(count)
                }
            }
        }

        for album in albums {
            album.childAlbumCount = albumCounts[album.id] ?? 0
            album.childPicCount = picCounts[album.id] ?? 0
        }
    }

    public func representativeThumbnails(forAlbumWithID albumID: String, limit: Int = 3) -> [Data] {
        let query = picsTable
            .filter(picAlbumId == albumID && picDateDeleted == nil)
            .select(picThumbnailData)
            .order(picDateAdded.desc)
            .limit(limit)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(picThumbnailData) }
    }

    public func representativeThumbnail(forAlbumWithID albumID: String, at offset: Int) -> Data? {
        let query = picsTable
            .filter(picAlbumId == albumID && picDateDeleted == nil)
            .select(picThumbnailData)
            .order(picDateAdded.desc)
            .limit(1, offset: offset)
        guard let row = try? database.pluck(query) else { return nil }
        return try? row.get(picThumbnailData)
    }

    /// Executes one small indexed query per album inside a single actor call,
    /// avoiding both actor serialization overhead and expensive window functions.
    public func batchRepresentativeThumbnails(
        forAlbumIDs albumIDs: [String], limit: Int = 3
    ) -> [String: [Data]] {
        guard !albumIDs.isEmpty else { return [:] }

        var result: [String: [Data]] = [:]
        for albumID in albumIDs {
            let query = picsTable
                .filter(picAlbumId == albumID && picDateDeleted == nil)
                .select(picThumbnailData)
                .order(picDateAdded.desc)
                .limit(limit)
            guard let rows = try? database.safeRows(query) else { continue }
            let thumbnails = rows.compactMap { try? $0.get(picThumbnailData) }
            if !thumbnails.isEmpty {
                result[albumID] = thumbnails
            }
        }
        return result
    }

    public func album(for id: String) -> Album? {
        let query = albumsTable.filter(albumId == id)
        return try? database.pluck(query).map { albumFrom(row: $0, loadChildren: false) }
    }

    public func createAlbum(_ name: String, parentAlbumID: String? = nil) -> Album {
        let id = UUID().uuidString
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let now = Date.now
        let album = Album(id: id, name: trimmedName, parentAlbumID: parentAlbumID, dateCreated: now)
        _ = try? database.run(albumsTable.insert(
            albumId <- id,
            albumName <- trimmedName,
            albumCoverPhoto <- nil,
            albumParentId <- parentAlbumID,
            albumDateCreated <- now.timeIntervalSince1970,
            syncDirty <- true,
            syncLastModified <- now.timeIntervalSince1970
        ))
        notifyLocalMutation()
        return album
    }

    public func renameAlbum(withID id: String, to newName: String) {
        let query = albumsTable.filter(albumId == id)
        _ = try? database.run(query.update(
            albumName <- newName.trimmingCharacters(in: .whitespaces),
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func updateAlbumCover(forAlbumWithID albumID: String, coverData: Data?) {
        let query = albumsTable.filter(albumId == albumID)
        _ = try? database.run(query.update(
            albumCoverPhoto <- coverData,
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func sortAlbum(_ albums: [Album], sortedBy sortType: SortType) -> [Album] {
        switch sortType {
        case .nameAscending: return albums.sorted(by: { $0.name < $1.name })
        case .nameDescending: return albums.sorted(by: { $0.name > $1.name })
        case .sizeAscending:
            let decorated = albums.map { ($0, $0.albumCount() + $0.picCount()) }
            return decorated.sorted(by: { $0.1 < $1.1 }).map(\.0)
        case .sizeDescending:
            let decorated = albums.map { ($0, $0.albumCount() + $0.picCount()) }
            return decorated.sorted(by: { $0.1 > $1.1 }).map(\.0)
        }
    }

    public func albumCount(forAlbumWithID id: String) -> Int {
        let query = albumsTable.filter(albumParentId == id)
        return (try? database.scalar(query.count)) ?? 0
    }

    public func picCount() -> Int {
        return (try? database.scalar(picsTable.filter(picDateDeleted == nil).count)) ?? 0
    }

    public func picCount(forAlbumWithID id: String) -> Int {
        let query = picsTable.filter(picAlbumId == id && picDateDeleted == nil)
        return (try? database.scalar(query.count)) ?? 0
    }

    public func albumCount() -> Int {
        return (try? database.scalar(albumsTable.count)) ?? 0
    }

    public func addAlbum(withID albumID: String, toAlbumWithID destinationAlbumID: String) {
        let query = albumsTable.filter(albumId == albumID)
        _ = try? database.run(query.update(
            albumParentId <- destinationAlbumID,
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func removeParentAlbum(forAlbumWithidentifier albumID: String) {
        let query = albumsTable.filter(albumId == albumID)
        _ = try? database.run(query.update(
            albumParentId <- nil,
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func deleteAlbum(withID albumID: String) {
        let parentID = parentAlbumID(forAlbumWithID: albumID)
        let now = syncTimestamp

        let picsQuery = picsTable.filter(picAlbumId == albumID)
        _ = try? database.run(picsQuery.update(
            picAlbumId <- parentID, picPinnedAt <- nil, syncDirty <- true, syncLastModified <- now
        ))

        let childAlbumsQuery = albumsTable.filter(albumParentId == albumID)
        _ = try? database.run(childAlbumsQuery.update(
            albumParentId <- parentID, syncDirty <- true, syncLastModified <- now
        ))

        if albumWasSynced(id: albumID) {
            recordTombstone(id: albumID, recordType: SyncRecordType.album)
        }
        let albumQuery = albumsTable.filter(albumId == albumID)
        _ = try? database.run(albumQuery.delete())

        let prefQuery = preferencesTable.filter(prefAlbumId == albumID)
        _ = try? database.run(prefQuery.delete())
        notifyLocalMutation()
    }

    @discardableResult
    public func deleteAlbumAndContents(withID albumID: String) -> [String] {
        var albumIDs = [albumID]
        var queue = [albumID]
        while let current = queue.popLast() {
            let childQuery = albumsTable.filter(albumParentId == current).select(albumId)
            if let rows = try? database.safeRows(childQuery) {
                for row in rows {
                    if let childID = try? row.get(albumId) {
                        albumIDs.append(childID)
                        queue.append(childID)
                    }
                }
            }
        }

        let picsQuery = picsTable.filter(albumIDs.contains(picAlbumId) && picDateDeleted == nil).select(picId)
        var deletedPicIDs: [String] = []
        if let rows = try? database.safeRows(picsQuery) {
            for row in rows {
                if let id = try? row.get(picId) {
                    deletedPicIDs.append(id)
                }
            }
        }
        deletePics(withIDs: deletedPicIDs)

        for id in albumIDs where albumWasSynced(id: id) {
            recordTombstone(id: id, recordType: SyncRecordType.album)
        }
        let albumQuery = albumsTable.filter(albumIDs.contains(albumId))
        _ = try? database.run(albumQuery.delete())

        let prefQuery = preferencesTable.filter(albumIDs.contains(prefAlbumId))
        _ = try? database.run(prefQuery.delete())
        notifyLocalMutation()
        return deletedPicIDs
    }

    public func parentAlbumID(forAlbumWithID albumID: String) -> String? {
        let query = albumsTable.filter(albumId == albumID).select(albumParentId)
        return try? database.pluck(query).flatMap { try? $0.get(albumParentId) }
    }

    /// Returns the ancestor chain for an album, ordered root-first and including the album itself.
    public func albumPath(forAlbumWithID albumID: String) -> [Album] {
        var chain: [Album] = []
        var currentID: String? = albumID
        var visited = Set<String>()
        while let id = currentID, !visited.contains(id) {
            visited.insert(id)
            guard let album = album(for: id) else { break }
            chain.append(album)
            currentID = album.parentAlbumID
        }
        return chain.reversed()
    }

    // MARK: - Search

    public func searchAlbums(matching searchText: String, sortedBy sortType: SortType) throws -> [Album] {
        let pattern = "%\(searchText)%"
        let query = albumsTable.filter(albumName.like(pattern, escape: nil))
        let rows = try database.safeRows(query)
        let albums = rows.map { row -> Album in
            albumFrom(row: row, loadChildren: false)
        }
        populateCounts(for: albums)
        return sortAlbum(albums, sortedBy: sortType)
    }

    public func searchAlbums(
        matching searchText: String, in parentAlbum: Album?, sortedBy sortType: SortType
    ) throws -> [Album] {
        let descendantIDs = descendantAlbumIDs(of: parentAlbum?.id)
        let pattern = "%\(searchText)%"
        let query = albumsTable.filter(
            descendantIDs.contains(albumId) && albumName.like(pattern, escape: nil)
        )
        let rows = try database.safeRows(query)
        let albums = rows.map { row -> Album in
            albumFrom(row: row, loadChildren: false)
        }
        populateCounts(for: albums)
        return sortAlbum(albums, sortedBy: sortType)
    }

    public func descendantAlbums(ofAlbumWithID albumID: String?) -> [Album] {
        let ids = descendantAlbumIDs(of: albumID)
        guard !ids.isEmpty else { return [] }
        let query = albumsTable.filter(ids.contains(albumId))
        let albums = (try? database.safeRows(query).map { albumFrom(row: $0, loadChildren: false) }) ?? []
        populateCounts(for: albums)
        return albums
    }

    private func descendantAlbumIDs(of parentID: String?) -> [String] {
        // Iterative BFS: one query per level instead of one query per node
        let firstQuery: QueryType
        if let parentID {
            firstQuery = albumsTable.filter(albumParentId == parentID).select(albumId)
        } else {
            firstQuery = albumsTable.filter(albumParentId == nil).select(albumId)
        }
        guard let rows = try? database.safeRows(firstQuery) else { return [] }
        var currentLevel = rows.compactMap { try? $0.get(albumId) }
        var allIDs = currentLevel

        while !currentLevel.isEmpty {
            let nextQuery = albumsTable
                .filter(currentLevel.contains(albumParentId))
                .select(albumId)
            guard let nextRows = try? database.safeRows(nextQuery) else { break }
            currentLevel = nextRows.compactMap { try? $0.get(albumId) }
            allIDs.append(contentsOf: currentLevel)
        }
        return allIDs
    }
}
