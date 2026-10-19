import Foundation
@preconcurrency import SQLite

public enum SyncRecordType: Sendable {
    public static let pic = "Pic"
    public static let album = "Album"
    public static let library = "Library"
}

extension Notification.Name {
    public static let dataActorDidMutateLocally = Notification.Name("DataActorDidMutateLocally")
}

public struct LibrarySyncSnapshot: Sendable {
    public let id: String
    public let name: String
    public let systemFields: Data?
    public let lastModified: Double

    public init(id: String, name: String, systemFields: Data? = nil, lastModified: Double) {
        self.id = id
        self.name = name
        self.systemFields = systemFields
        self.lastModified = lastModified
    }
}

public struct PicSyncSnapshot: Sendable {
    public let id: String
    public let name: String
    public let albumID: String?
    public let dateAdded: Double
    public let mediaType: Int
    public let duration: Double?
    public let thumbnail: Data?
    public let systemFields: Data?
    public let lastModified: Double

    public init(
        id: String,
        name: String,
        albumID: String? = nil,
        dateAdded: Double,
        mediaType: Int,
        duration: Double? = nil,
        thumbnail: Data? = nil,
        systemFields: Data? = nil,
        lastModified: Double
    ) {
        self.id = id
        self.name = name
        self.albumID = albumID
        self.dateAdded = dateAdded
        self.mediaType = mediaType
        self.duration = duration
        self.thumbnail = thumbnail
        self.systemFields = systemFields
        self.lastModified = lastModified
    }
}

public struct AlbumSyncSnapshot: Sendable {
    public let id: String
    public let name: String
    public let parentAlbumID: String?
    public let dateCreated: Double
    public let systemFields: Data?
    public let lastModified: Double

    public init(
        id: String,
        name: String,
        parentAlbumID: String? = nil,
        dateCreated: Double,
        systemFields: Data? = nil,
        lastModified: Double
    ) {
        self.id = id
        self.name = name
        self.parentAlbumID = parentAlbumID
        self.dateCreated = dateCreated
        self.systemFields = systemFields
        self.lastModified = lastModified
    }
}

public struct OriginalLocation: Sendable {
    public let mediaType: MediaType
    public let filename: String?
    public let localURL: URL?

    public init(mediaType: MediaType, filename: String? = nil, localURL: URL? = nil) {
        self.mediaType = mediaType
        self.filename = filename
        self.localURL = localURL
    }
}

extension DataActor {

    public var syncTimestamp: Double { Date.now.timeIntervalSince1970 }

    public nonisolated func notifyLocalMutation() {
        NotificationCenter.default.post(name: .dataActorDidMutateLocally, object: collectionID)
    }

    public func recordTombstone(id: String, recordType: String) {
        _ = try? database.run(tombstonesTable.insert(or: .replace,
            tombstoneId <- id,
            tombstoneRecordType <- recordType,
            tombstoneDeletedAt <- syncTimestamp
        ))
    }

    public func recordTombstones(ids: [String], recordType: String) {
        for id in ids {
            recordTombstone(id: id, recordType: recordType)
        }
    }

    public func picWasSynced(id: String) -> Bool {
        let query = picsTable.filter(picId == id).select(syncCKSystemFields)
        guard let row = try? database.pluck(query) else { return false }
        return ((try? row.get(syncCKSystemFields)) ?? nil) != nil
    }

    public func syncedPicIDs(among ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let query = picsTable
            .filter(ids.contains(picId) && syncCKSystemFields != nil)
            .select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func albumWasSynced(id: String) -> Bool {
        let query = albumsTable.filter(albumId == id).select(syncCKSystemFields)
        guard let row = try? database.pluck(query) else { return false }
        return ((try? row.get(syncCKSystemFields)) ?? nil) != nil
    }

    // MARK: - Upload: dirty records + tombstones

    public func dirtyAlbumIDs() -> [String] {
        (try? database.safeRows(albumsTable.filter(syncDirty == true).select(albumId))
            .map { $0[albumId] }) ?? []
    }

    public func dirtyPicIDs() -> [String] {
        (try? database.safeRows(picsTable.filter(syncDirty == true).select(picId))
            .map { $0[picId] }) ?? []
    }

    public func unsyncedAlbumIDs() -> [String] {
        (try? database.safeRows(albumsTable.filter(syncCKSystemFields == nil).select(albumId))
            .map { $0[albumId] }) ?? []
    }

    public func unsyncedPicIDs() -> [String] {
        (try? database.safeRows(picsTable.filter(syncCKSystemFields == nil).select(picId))
            .map { $0[picId] }) ?? []
    }

    public func pendingTombstones() -> [(id: String, recordType: String)] {
        (try? database.safeRows(tombstonesTable)
            .map { (id: $0[tombstoneId], recordType: $0[tombstoneRecordType]) }) ?? []
    }

    public func removeTombstone(id: String) {
        _ = try? database.run(tombstonesTable.filter(tombstoneId == id).delete())
    }

    public func albumSyncSnapshot(forID id: String) -> AlbumSyncSnapshot? {
        guard let row = try? database.pluck(albumsTable.filter(albumId == id)) else { return nil }
        return AlbumSyncSnapshot(
            id: id,
            name: (try? row.get(albumName)) ?? "",
            parentAlbumID: try? row.get(albumParentId),
            dateCreated: (try? row.get(albumDateCreated)) ?? 0,
            systemFields: try? row.get(syncCKSystemFields),
            lastModified: (try? row.get(syncLastModified)) ?? 0
        )
    }

    public func picSyncSnapshot(forID id: String) -> PicSyncSnapshot? {
        guard let row = try? database.pluck(picsTable.filter(picId == id)) else { return nil }
        return PicSyncSnapshot(
            id: id,
            name: (try? row.get(picName)) ?? "",
            albumID: try? row.get(picAlbumId),
            dateAdded: (try? row.get(picDateAdded)) ?? 0,
            mediaType: (try? row.get(picMediaType)) ?? 0,
            duration: try? row.get(picDuration),
            thumbnail: try? row.get(picThumbnailData),
            systemFields: try? row.get(syncCKSystemFields),
            lastModified: (try? row.get(syncLastModified)) ?? 0
        )
    }

    public func markAlbumSynced(id: String, systemFields: Data?) {
        _ = try? database.run(albumsTable.filter(albumId == id)
            .update(syncDirty <- false, syncCKSystemFields <- systemFields))
    }

    public func markPicSynced(id: String, systemFields: Data?) {
        _ = try? database.run(picsTable.filter(picId == id)
            .update(syncDirty <- false, syncCKSystemFields <- systemFields))
    }

    public func picIDsNeedingOriginalUpload() -> [String] {
        let query = picsTable
            .filter(picFilePath != nil && syncOriginalSynced == false)
            .select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func originalLocation(forPicWithID id: String) -> OriginalLocation? {
        let query = picsTable.filter(picId == id).select(picFilePath, picMediaType)
        guard let row = try? database.pluck(query) else { return nil }
        let mediaType = MediaType(rawValue: (try? row.get(picMediaType)) ?? 0) ?? .pic
        let path = (try? row.get(picFilePath)) ?? nil
        switch mediaType {
        case .pic:
            let url = path.map { imageFileURL(forRelativePath: $0) }
            let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return OriginalLocation(mediaType: .pic, filename: id, localURL: exists ? url : nil)
        case .video:
            let filename = path.map { ($0 as NSString).lastPathComponent }
            let url = path.map { videoFileURL(forRelativePath: $0) }
            let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return OriginalLocation(mediaType: .video, filename: filename, localURL: exists ? url : nil)
        }
    }

    public func markPicOriginalSynced(id: String) {
        _ = try? database.run(picsTable.filter(picId == id).update(syncOriginalSynced <- true))
    }

    public func resetOriginalSyncState() {
        _ = try? database.run(picsTable.update(syncOriginalSynced <- false))
    }

    public func localOriginalPicIDs(inAlbum albumID: String) -> [String] {
        let query = picsTable
            .filter(picAlbumId == albumID && picFilePath != nil)
            .select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func localOriginalPicIDs() -> [String] {
        let query = picsTable.filter(picFilePath != nil).select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func allOriginalPicIDs() -> [String] {
        (try? database.safeRows(picsTable.select(picId)).map { $0[picId] }) ?? []
    }

    public func allOriginalPicIDs(inAlbum albumID: String) -> [String] {
        let query = picsTable.filter(picAlbumId == albumID).select(picId)
        return (try? database.safeRows(query).map { $0[picId] }) ?? []
    }

    public func evictLocalOriginal(picID: String) {
        let query = picsTable.filter(picId == picID).select(picFilePath, picMediaType)
        guard let row = try? database.pluck(query),
              let path = (try? row.get(picFilePath)) ?? nil else { return }
        let mediaType = MediaType(rawValue: (try? row.get(picMediaType)) ?? 0) ?? .pic
        if mediaType == .video {
            deleteVideoFile(atRelativePath: path)
            _ = try? database.run(picsTable.filter(picId == picID).update(picFilePath <- nil))
        } else if isImagePath(path) {
            deleteImageFile(atRelativePath: path)
            _ = try? database.run(picsTable.filter(picId == picID).update(picFilePath <- nil))
        }
    }

    // MARK: - Download: apply remote changes

    public func applyRemoteAlbum(_ snapshot: AlbumSyncSnapshot) {
        let exists = ((try? database.scalar(albumsTable.filter(albumId == snapshot.id).count)) ?? 0) > 0
        if exists {
            _ = try? database.run(albumsTable.filter(albumId == snapshot.id).update(
                albumName <- snapshot.name,
                albumParentId <- snapshot.parentAlbumID,
                albumDateCreated <- snapshot.dateCreated,
                syncDirty <- false,
                syncCKSystemFields <- snapshot.systemFields,
                syncLastModified <- snapshot.lastModified
            ))
        } else {
            _ = try? database.run(albumsTable.insert(or: .replace,
                albumId <- snapshot.id,
                albumName <- snapshot.name,
                albumCoverPhoto <- nil,
                albumParentId <- snapshot.parentAlbumID,
                albumDateCreated <- snapshot.dateCreated,
                syncDirty <- false,
                syncCKSystemFields <- snapshot.systemFields,
                syncLastModified <- snapshot.lastModified
            ))
        }
    }

    public func applyRemotePic(_ snapshot: PicSyncSnapshot) {
        let exists = ((try? database.scalar(picsTable.filter(picId == snapshot.id).count)) ?? 0) > 0
        if exists {
            _ = try? database.run(picsTable.filter(picId == snapshot.id).update(
                picName <- snapshot.name,
                picAlbumId <- snapshot.albumID,
                picDateAdded <- snapshot.dateAdded,
                picMediaType <- snapshot.mediaType,
                picDuration <- snapshot.duration,
                picThumbnailData <- snapshot.thumbnail,
                syncDirty <- false,
                syncCKSystemFields <- snapshot.systemFields,
                syncLastModified <- snapshot.lastModified
            ))
        } else {
            _ = try? database.run(picsTable.insert(or: .replace,
                picId <- snapshot.id,
                picName <- snapshot.name,
                picAlbumId <- snapshot.albumID,
                picDateAdded <- snapshot.dateAdded,
                picThumbnailData <- snapshot.thumbnail,
                picMediaType <- snapshot.mediaType,
                picDuration <- snapshot.duration,
                syncDirty <- false,
                syncCKSystemFields <- snapshot.systemFields,
                syncLastModified <- snapshot.lastModified
            ))
        }
    }

    public func removeAlbumForRemoteDelete(id: String) {
        _ = try? database.run(albumsTable.filter(albumId == id).delete())
        _ = try? database.run(preferencesTable.filter(prefAlbumId == id).delete())
    }

    public func removePicForRemoteDelete(id: String) {
        let selectQuery = picsTable.filter(picId == id).select(picFilePath)
        if let row = try? database.pluck(selectQuery),
           let path = try? row.get(picFilePath) {
            if isImagePath(path) {
                deleteImageFile(atRelativePath: path)
            } else {
                deleteVideoFile(atRelativePath: path)
            }
        }
        _ = try? database.run(picsTable.filter(picId == id).delete())
    }
}
