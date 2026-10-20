import Foundation
@preconcurrency import SQLite

extension DataActor {
    private var picListColumns: [Expressible] {
        [picId, picName, picAlbumId, picDateAdded, picThumbnailData,
         picMediaType, picDuration, picFilePath]
    }

    private var picSkeletonColumns: [Expressible] {
        [picId, picName, picAlbumId, picDateAdded, picMediaType, picDuration, picFilePath]
    }

    public func pics() throws -> [Pic] {
        let query = picsTable
            .filter(picDateDeleted == nil)
            .select(picListColumns)
            .order(picDateAdded.desc)
        return try database.safeRows(query).map { picFrom(row: $0) }
    }

    public func pics(in album: Album?, order: SortOrder) throws -> [Pic] {
        let baseQuery: SQLite.Table
        if let albumID = album?.id {
            baseQuery = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil)
        } else {
            baseQuery = picsTable.filter(picAlbumId == nil && picDateDeleted == nil)
        }
        let orderedQuery = (order == .reverse ? baseQuery.order(picDateAdded.desc) :
                                                baseQuery.order(picDateAdded.asc))
            .select(picListColumns)
        return try database.safeRows(orderedQuery).map { picFrom(row: $0) }
    }

    public func pics(withIDs ids: [String]) throws -> [Pic] {
        guard !ids.isEmpty else { return [] }
        let query = picsTable
            .filter(ids.contains(picId) && picDateDeleted == nil)
            .select(picListColumns)
        let fetched = try database.safeRows(query).map { picFrom(row: $0) }
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    public func picSkeletons(in album: Album?, order: SortOrder) throws -> [Pic] {
        let baseQuery: SQLite.Table
        if let albumID = album?.id {
            baseQuery = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil)
        } else {
            baseQuery = picsTable.filter(picAlbumId == nil && picDateDeleted == nil)
        }
        let orderedQuery = (order == .reverse ? baseQuery.order(picDateAdded.desc) :
                                                baseQuery.order(picDateAdded.asc))
            .select(picSkeletonColumns)
        return try database.safeRows(orderedQuery).map { picFrom(row: $0) }
    }

    public func picSkeletons(in album: Album?, order: SortOrder, limit: Int, offset: Int) throws -> [Pic] {
        let baseQuery: SQLite.Table
        if let albumID = album?.id {
            baseQuery = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil)
        } else {
            baseQuery = picsTable.filter(picAlbumId == nil && picDateDeleted == nil)
        }
        let orderedQuery = (order == .reverse ? baseQuery.order(picDateAdded.desc) :
                                                baseQuery.order(picDateAdded.asc))
            .select(picSkeletonColumns)
            .limit(limit, offset: offset)
        return try database.safeRows(orderedQuery).map { picFrom(row: $0) }
    }

    public func picSkeletonsByName(in album: Album?, order: SortOrder) throws -> [Pic] {
        let baseQuery: SQLite.Table
        if let albumID = album?.id {
            baseQuery = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil)
        } else {
            baseQuery = picsTable.filter(picAlbumId == nil && picDateDeleted == nil)
        }
        let query = baseQuery.select(picSkeletonColumns)
        let pics = try database.safeRows(query).map { picFrom(row: $0) }
        return pics.sorted { lhs, rhs in
            let result = lhs.name.localizedStandardCompare(rhs.name)
            return order == .reverse ? result == .orderedDescending : result == .orderedAscending
        }
    }

    public func picCount(in album: Album?) -> Int {
        let query: SQLite.Table
        if let albumID = album?.id {
            query = picsTable.filter(picAlbumId == albumID && picDateDeleted == nil)
        } else {
            query = picsTable.filter(picAlbumId == nil && picDateDeleted == nil)
        }
        return (try? database.scalar(query.count)) ?? 0
    }

    public func allPicSkeletons() throws -> [Pic] {
        let query = picsTable
            .filter(picDateDeleted == nil)
            .select(picSkeletonColumns)
            .order(picDateAdded.desc)
        return try database.safeRows(query).map { picFrom(row: $0) }
    }

    public func recentThumbnails(limit: Int) -> [Data] {
        let query = picsTable
            .filter(picThumbnailData != nil && picDateDeleted == nil)
            .select(picThumbnailData)
            .order(picDateAdded.desc)
            .limit(limit)
        return ((try? database.safeRows(query)) ?? []).compactMap { try? $0.get(picThumbnailData) }
    }

    public func thumbnails(forPicIDs ids: [String]) -> [Data] {
        guard !ids.isEmpty else { return [] }
        let query = picsTable
            .filter(ids.contains(picId) && picDateDeleted == nil)
            .select(picId, picThumbnailData)
        var byID: [String: Data] = [:]
        for row in (try? database.safeRows(query)) ?? [] {
            if let id = try? row.get(picId), let data = try? row.get(picThumbnailData) {
                byID[id] = data
            }
        }
        return ids.compactMap { byID[$0] }
    }

    public func thumbnailData(forPicWithID id: String) -> Data? {
        let query = picsTable
            .filter(picId == id)
            .select(picThumbnailData)
        return try? database.pluck(query).flatMap { try? $0.get(picThumbnailData) }
    }

    public func imageData(forPicWithID id: String) -> Data? {
        let metaQuery = picsTable
            .filter(picId == id)
            .select(picFilePath, picMediaType)
        if let row = try? database.pluck(metaQuery) {
            let mediaType = (try? row.get(picMediaType)) ?? 0
            if mediaType == MediaType.pic.rawValue,
               let path = try? row.get(picFilePath),
               let data = try? Data(contentsOf: imageFileURL(forRelativePath: path)),
               !data.isEmpty {
                return data
            }
        }
        let blobQuery = picsTable
            .filter(picId == id)
            .select(picData)
        return try? database.pluck(blobQuery).flatMap { try? $0.get(picData) }
    }

    public func rawBlobData(forPicWithID id: String) -> Data? {
        let query = picsTable
            .filter(picId == id)
            .select(picData)
        return try? database.pluck(query).flatMap { try? $0.get(picData) }
    }

    public func createPic(_ name: String, data: Data, inAlbumWithID albumID: String? = nil, dateAdded: Date? = nil) {
        let id = UUID().uuidString
        let now = dateAdded ?? Date.now
        let thumbnailData = Pic.makeThumbnail(data)
        guard let relativePath = saveImageFile(data, id: id) else { return }
        _ = try? database.run(picsTable.insert(
            picId <- id,
            picName <- name,
            picAlbumId <- albumID,
            picDateAdded <- now.timeIntervalSince1970,
            picThumbnailData <- thumbnailData,
            picMediaType <- MediaType.pic.rawValue,
            picFilePath <- relativePath,
            syncDirty <- true,
            syncLastModified <- now.timeIntervalSince1970
        ))
        notifyLocalMutation()
    }

    public func createVideo(
        _ name: String,
        data: Data,
        duration: TimeInterval,
        fileExtension: String,
        inAlbumWithID albumID: String? = nil,
        dateAdded: Date? = nil
    ) async {
        let id = UUID().uuidString
        let now = dateAdded ?? Date.now
        guard let relativePath = saveVideoFile(data, id: id, fileExtension: fileExtension) else {
            return
        }
        let videoURL = videoFileURL(forRelativePath: relativePath)
        let thumbnailData = await Pic.makeVideoThumbnail(videoURL)
        _ = try? database.run(picsTable.insert(
            picId <- id,
            picName <- name,
            picAlbumId <- albumID,
            picDateAdded <- now.timeIntervalSince1970,
            picThumbnailData <- thumbnailData,
            picMediaType <- MediaType.video.rawValue,
            picDuration <- duration,
            picFilePath <- relativePath,
            syncDirty <- true,
            syncLastModified <- now.timeIntervalSince1970
        ))
        notifyLocalMutation()
    }

    public func addPics(withIDs picIDs: [String], toAlbumWithID albumID: String) {
        guard !picIDs.isEmpty else { return }
        let query = picsTable.filter(picIDs.contains(picId))
        _ = try? database.run(query.update(
            picAlbumId <- albumID, syncDirty <- true, syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func addPic(withID picID: String, toAlbumWithID albumID: String) {
        let query = picsTable.filter(picId == picID)
        _ = try? database.run(query.update(
            picAlbumId <- albumID, syncDirty <- true, syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func removeParentAlbum(forPicsWithIDs picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let query = picsTable.filter(picIDs.contains(picId))
        _ = try? database.run(query.update(
            picAlbumId <- nil, syncDirty <- true, syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func setAsAlbumCover(for picID: String) {
        let data = imageData(forPicWithID: picID) ?? thumbnailData(forPicWithID: picID)
        if let data,
           let albumID = containingAlbumID(forPicWithID: picID) {
            let coverData = Album.makeCover(data)
            let query = albumsTable.filter(albumId == albumID)
            _ = try? database.run(query.update(
                albumCoverPhoto <- coverData, syncDirty <- true, syncLastModified <- syncTimestamp
            ))
            notifyLocalMutation()
        }
    }

    public func picName(forPicWithID picID: String) -> String? {
        let query = picsTable
            .filter(picId == picID)
            .select(picName)
        return try? database.pluck(query).map { $0[picName] }
    }

    public func renamePic(withID picID: String, to newName: String) {
        let query = picsTable.filter(picId == picID)
        _ = try? database.run(query.update(
            picName <- newName, syncDirty <- true, syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    public func updateThumbnail(forPicWithID picID: String, thumbnailData: Data?) {
        let query = picsTable.filter(picId == picID)
        _ = try? database.run(query.update(
            picThumbnailData <- thumbnailData, syncDirty <- true, syncLastModified <- syncTimestamp
        ))
        notifyLocalMutation()
    }

    private func containingAlbumID(forPicWithID picID: String) -> String? {
        let query = picsTable
            .filter(picId == picID)
            .select(picAlbumId)
        return try? database.pluck(query).flatMap { try? $0.get(picAlbumId) }
    }

    public func deletePic(withID picID: String) {
        let selectQuery = picsTable.filter(picId == picID).select(picFilePath)
        if let row = try? database.pluck(selectQuery),
           let path = try? row.get(picFilePath) {
            deleteMediaFile(atRelativePath: path)
        }
        if picWasSynced(id: picID) {
            recordTombstone(id: picID, recordType: SyncRecordType.pic)
        }
        let query = picsTable.filter(picId == picID)
        _ = try? database.run(query.delete())
        notifyLocalMutation()
    }

    public func deletePics(withIDs picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let selectQuery = picsTable.filter(picIDs.contains(picId)).select(picFilePath)
        if let rows = try? database.safeRows(selectQuery) {
            for row in rows {
                if let path = try? row.get(picFilePath) {
                    deleteMediaFile(atRelativePath: path)
                }
            }
        }
        recordTombstones(ids: syncedPicIDs(among: picIDs), recordType: SyncRecordType.pic)
        let query = picsTable.filter(picIDs.contains(picId))
        _ = try? database.run(query.delete())
        notifyLocalMutation()
    }

    private func deleteMediaFile(atRelativePath path: String) {
        if isImagePath(path) {
            deleteImageFile(atRelativePath: path)
        } else {
            deleteVideoFile(atRelativePath: path)
        }
    }

    public func videoURL(forPicWithID picID: String) -> URL? {
        let query = picsTable.filter(picId == picID).select(picFilePath)
        guard let row = try? database.pluck(query),
              let path = (try? row.get(picFilePath)) ?? nil else { return nil }
        let url = videoFileURL(forRelativePath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Thumbnails

    public func deleteAllThumbnails() {
        _ = try? database.run(picsTable.update(picThumbnailData <- nil))
    }

    // MARK: - Delete All

    public func deleteAll() {
        try? FileManager.default.removeItem(at: imagesDirectoryURL())
        try? FileManager.default.removeItem(at: videosDirectoryURL())
        _ = try? database.run(picsTable.delete())
        _ = try? database.run(albumsTable.delete())
    }
}
