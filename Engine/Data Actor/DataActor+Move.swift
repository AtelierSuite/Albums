import Foundation
@preconcurrency import SQLite

public struct AlbumMoveRecord: Sendable {
    public let id: String
    public let name: String
    public let coverPhoto: Data?
    public let parentAlbumID: String?
    public let dateCreated: Double

    public init(
        id: String,
        name: String,
        coverPhoto: Data? = nil,
        parentAlbumID: String? = nil,
        dateCreated: Double
    ) {
        self.id = id
        self.name = name
        self.coverPhoto = coverPhoto
        self.parentAlbumID = parentAlbumID
        self.dateCreated = dateCreated
    }
}

public struct PicMoveRecord: Sendable {
    public let id: String
    public let name: String
    public let albumID: String?
    public let dateAdded: Double
    public let thumbnail: Data?
    public let mediaType: Int
    public let duration: Double?
    public let filePath: String?

    public init(
        id: String,
        name: String,
        albumID: String? = nil,
        dateAdded: Double,
        thumbnail: Data? = nil,
        mediaType: Int,
        duration: Double? = nil,
        filePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.albumID = albumID
        self.dateAdded = dateAdded
        self.thumbnail = thumbnail
        self.mediaType = mediaType
        self.duration = duration
        self.filePath = filePath
    }

    public var resolvedMediaType: MediaType { MediaType(rawValue: mediaType) ?? .pic }
}

extension DataActor {

    // MARK: - Collision checks

    public func existingAlbumIDs(among ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let query = albumsTable.filter(ids.contains(albumId)).select(albumId)
        return (try? database.safeRows(query).map { $0[albumId] }) ?? []
    }

    public func existingPicIDs(among ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let query = picsTable.filter(ids.contains(picId)).select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    // MARK: - Subtree collection

    public func collectSubtree(forAlbumID albumID: String) -> (albumIDs: [String], picIDs: [String]) {
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
        var picIDs: [String] = []
        let picsQuery = picsTable.filter(albumIDs.contains(picAlbumId) && picDateDeleted == nil).select(picId)
        if let rows = try? database.safeRows(picsQuery) {
            for row in rows {
                if let id = try? row.get(picId) { picIDs.append(id) }
            }
        }
        return (albumIDs, picIDs)
    }

    // MARK: - Move-record reads

    public func albumRecordForMove(id: String) -> AlbumMoveRecord? {
        guard let row = try? database.pluck(albumsTable.filter(albumId == id)) else { return nil }
        return AlbumMoveRecord(
            id: id,
            name: (try? row.get(albumName)) ?? "",
            coverPhoto: (try? row.get(albumCoverPhoto)) ?? nil,
            parentAlbumID: (try? row.get(albumParentId)) ?? nil,
            dateCreated: (try? row.get(albumDateCreated)) ?? 0
        )
    }

    public func picRecordForMove(id: String) -> PicMoveRecord? {
        guard let row = try? database.pluck(picsTable.filter(picId == id)) else { return nil }
        return PicMoveRecord(
            id: id,
            name: (try? row.get(picName)) ?? "",
            albumID: (try? row.get(picAlbumId)) ?? nil,
            dateAdded: (try? row.get(picDateAdded)) ?? 0,
            thumbnail: (try? row.get(picThumbnailData)) ?? nil,
            mediaType: (try? row.get(picMediaType)) ?? 0,
            duration: (try? row.get(picDuration)) ?? nil,
            filePath: (try? row.get(picFilePath)) ?? nil
        )
    }

    public func storedPreferences(forAlbumWithID albumID: String) -> AlbumPreferences? {
        let query = preferencesTable.filter(prefAlbumId == albumID)
        guard let row = try? database.pluck(query) else { return nil }
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

    // MARK: - Move-record inserts (explicit IDs, new sync zone)

    public func insertMovedAlbum(_ record: AlbumMoveRecord, parentAlbumID newParentID: String?) {
        _ = try? database.run(albumsTable.insert(
            albumId <- record.id,
            albumName <- record.name,
            albumCoverPhoto <- record.coverPhoto,
            albumParentId <- newParentID,
            albumDateCreated <- record.dateCreated,
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ))
    }

    public func insertMovedPic(_ record: PicMoveRecord, albumID newAlbumID: String?,
                               filePath: String?, originalSynced: Bool) {
        _ = try? database.run(picsTable.insert(
            picId <- record.id,
            picName <- record.name,
            picAlbumId <- newAlbumID,
            picDateAdded <- record.dateAdded,
            picThumbnailData <- record.thumbnail,
            picMediaType <- record.mediaType,
            picDuration <- record.duration,
            picFilePath <- filePath,
            syncDirty <- true,
            syncOriginalSynced <- originalSynced,
            syncLastModified <- syncTimestamp
        ))
    }

    // MARK: - Local file adoption (copy an original into this library's store)

    public func adoptImageFile(from sourceURL: URL, id: String) -> String? {
        ensureImagesDirectoryExists()
        let relativePath = "\(Self.imagesDirectoryName)/\(id)"
        let destinationURL = imageFileURL(forRelativePath: relativePath)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return relativePath
        } catch {
            debugPrint("Failed to adopt image file: \(error)")
            return nil
        }
    }

    public func adoptVideoFile(from sourceURL: URL, id: String, fileExtension: String) -> String? {
        ensureVideosDirectoryExists()
        let filename = "\(id).\(fileExtension)"
        let relativePath = "\(Self.videosDirectoryName)/\(filename)"
        let destinationURL = videoFileURL(forRelativePath: relativePath)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return relativePath
        } catch {
            debugPrint("Failed to adopt video file: \(error)")
            return nil
        }
    }

    public func deleteAdoptedFile(atRelativePath path: String) {
        if isImagePath(path) {
            deleteImageFile(atRelativePath: path)
        } else {
            deleteVideoFile(atRelativePath: path)
        }
    }

    public func deleteMovedRecords(albumIDs: [String], picIDs: [String]) {
        if !picIDs.isEmpty {
            let selectQuery = picsTable.filter(picIDs.contains(picId)).select(picFilePath)
            if let rows = try? database.safeRows(selectQuery) {
                for row in rows {
                    if let path = try? row.get(picFilePath) {
                        deleteAdoptedFile(atRelativePath: path)
                    }
                }
            }
            _ = try? database.run(picsTable.filter(picIDs.contains(picId)).delete())
        }
        if !albumIDs.isEmpty {
            _ = try? database.run(albumsTable.filter(albumIDs.contains(albumId)).delete())
            deletePreferences(forAlbumIDs: albumIDs)
        }
    }
}
