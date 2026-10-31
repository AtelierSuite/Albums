import Foundation
@preconcurrency import SQLite
import SwiftUI

public actor DataActor {

    nonisolated(unsafe) private static var _shared = DataActor(collectionID: PicLibrary.persistedCurrentID)
    public static var shared: DataActor { _shared }

    nonisolated(unsafe) private static var instances: [String: DataActor] = [:]
    private static let instancesLock = NSLock()

    public static func switchLibrary(to collectionID: String) {
        instancesLock.lock()
        instances[collectionID] = nil
        instancesLock.unlock()
        _shared = DataActor(collectionID: collectionID)
    }

    public static func instance(for collectionID: String) -> DataActor {
        if _shared.collectionID == collectionID { return _shared }
        instancesLock.lock()
        defer { instancesLock.unlock() }
        if let existing = instances[collectionID] { return existing }
        let actor = DataActor(collectionID: collectionID)
        instances[collectionID] = actor
        return actor
    }

    public nonisolated let collectionID: String
    public let database: Connection
    public let databaseURL: URL
    private var isIncrementalAutoVacuumActive: Bool

    public let albumsTable = Table("albums")
    public let picsTable = Table("pics")
    public let preferencesTable = Table("album_preferences")

    public let albumId = Expression<String>("id")
    public let albumName = Expression<String>("name")
    public let albumCoverPhoto = Expression<Data?>("cover_photo")
    public let albumParentId = Expression<String?>("parent_album_id")
    public let albumDateCreated = Expression<Double>("date_created")

    public let picId = Expression<String>("id")
    public let picName = Expression<String>("name")
    public let picAlbumId = Expression<String?>("containing_album_id")
    public let picDateAdded = Expression<Double>("date_added")
    public let picData = Expression<Data?>("data")
    public let picThumbnailData = Expression<Data?>("thumbnail_data")
    public let picMediaType = Expression<Int>("media_type")
    public let picDuration = Expression<Double?>("duration")
    public let picFilePath = Expression<String?>("file_path")
    public let picPinnedAt = Expression<Double?>("pinned_at")
    public let picThumbnailAspectRatio = Expression<Double?>("thumbnail_aspect_ratio")
    public let picContentCredentials = Expression<String?>("content_credentials")
    public let picContentCredentialsVersion = Expression<Int>("content_credentials_version")
    public let picAIContent = Expression<Int?>("ai_content")

    public let prefAlbumId = Expression<String>("album_id")
    public let prefAlbumSort = Expression<String>("album_sort")
    public let prefAlbumViewStyle = Expression<String>("album_view_style")
    public let prefAlbumColumnCount = Expression<Int>("album_column_count")
    public let prefPicSort = Expression<String>("pic_sort")
    public let prefPicColumnCount = Expression<Int>("pic_column_count")
    public let prefHideSectionHeaders = Expression<Bool>("hide_section_headers")

    public let syncDirty = Expression<Bool>("dirty")
    public let syncLastModified = Expression<Double>("last_modified")
    public let syncCKSystemFields = Expression<Data?>("ck_system_fields")
    public let syncOriginalSynced = Expression<Bool>("original_synced")

    public let tombstonesTable = Table("tombstones")
    public let tombstoneId = Expression<String>("id")
    public let tombstoneRecordType = Expression<String>("record_type")
    public let tombstoneDeletedAt = Expression<Double>("deleted_at")

    public let migrationsTable = Table("migrations")
    public let migrationName = Expression<String>("migration_name")
    public let migrationAppVersion = Expression<String>("app_version")
    public let migrationCompleted = Expression<Bool>("completed")

    public init(collectionID: String) {
        self.collectionID = collectionID
        let databaseFileName = "Collection.db"
        let fileManager = FileManager.default

        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            if collectionID == PicLibrary.defaultID {
                self.databaseURL = appGroupURL.appendingPathComponent(databaseFileName)
            } else {
                let folderURL = appGroupURL.appendingPathComponent(collectionID)
                try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                self.databaseURL = folderURL.appendingPathComponent(databaseFileName)
            }
        } else {
            fatalError()
        }

        let database: Connection
        do {
            database = try Connection(self.databaseURL.path)
        } catch {
            fatalError("Could not open SQLite database: \(error)")
        }
        self.database = database
        _ = try? database.execute("PRAGMA journal_mode = WAL;")
        // PRAGMA auto_vacuum reports the requested value immediately, even before
        // a VACUUM applies it, so read the real mode before requesting the change.
        let activeAutoVacuumMode = (try? database.scalar("PRAGMA auto_vacuum")) as? Int64 ?? 0
        self.isIncrementalAutoVacuumActive = activeAutoVacuumMode == 2
        _ = try? database.execute("PRAGMA auto_vacuum = INCREMENTAL;")
        do {
            try database.run(albumsTable.create(ifNotExists: true) { table in
                table.column(albumId, primaryKey: true)
                table.column(albumName)
                table.column(albumCoverPhoto)
                table.column(albumParentId)
                table.column(albumDateCreated)
            })

            try database.run(picsTable.create(ifNotExists: true) { table in
                table.column(picId, primaryKey: true)
                table.column(picName)
                table.column(picAlbumId)
                table.column(picDateAdded)
                table.column(picThumbnailData)
                table.column(picMediaType, defaultValue: 0)
                table.column(picDuration)
                table.column(picFilePath)
            })
            if DatabaseMigrator.migrationNeeded() {
                DatabaseMigrator.migrateCollectionDatabase(database,
                    albumsTable: albumsTable, picsTable: picsTable,
                    preferencesTable: preferencesTable)
            }

            try database.run(preferencesTable.create(ifNotExists: true) { table in
                table.column(prefAlbumId, primaryKey: true)
                table.column(prefAlbumSort, defaultValue: "nameAscending")
                table.column(prefAlbumViewStyle, defaultValue: "grid")
                table.column(prefAlbumColumnCount, defaultValue: 4)
                table.column(prefPicSort, defaultValue: "dateAddedDescending")
                table.column(prefPicColumnCount, defaultValue: 4)
                table.column(prefHideSectionHeaders, defaultValue: false)
            })

            for table in [albumsTable, picsTable, preferencesTable] {
                _ = try? database.run(table.addColumn(syncDirty, defaultValue: true))
                _ = try? database.run(table.addColumn(syncLastModified, defaultValue: 0))
                _ = try? database.run(table.addColumn(syncCKSystemFields))
            }
            _ = try? database.run(picsTable.addColumn(syncOriginalSynced, defaultValue: false))
            DatabaseMigrator.migratePinsColumn(database, picsTable: picsTable)
            DatabaseMigrator.migrateRecentlyDeleted(database, picsTable: picsTable)
            DatabaseMigrator.migrateThumbnailAspectRatio(database, picsTable: picsTable)
            DatabaseMigrator.migrateContentCredentials(database, picsTable: picsTable)
            try database.run(tombstonesTable.create(ifNotExists: true) { table in
                table.column(tombstoneId, primaryKey: true)
                table.column(tombstoneRecordType)
                table.column(tombstoneDeletedAt, defaultValue: 0)
            })

            try database.run(migrationsTable.create(ifNotExists: true) { table in
                table.column(migrationName, primaryKey: true)
                table.column(migrationAppVersion, defaultValue: "")
                table.column(migrationCompleted, defaultValue: false)
            })
            DatabaseMigrator.markAlbumCoversForSync(database)

            try database.run(albumsTable.createIndex(albumParentId, ifNotExists: true))
            try database.run(picsTable.createIndex(picAlbumId, ifNotExists: true))
            DatabaseMigrator.createSearchIndexes(database)

            DatabaseMigrator.stampSchemaVersionIfMigrated(database)
        } catch {
            debugPrint("Database setup error: \(error)")
        }
    }

    /// Current auto_vacuum mode: 0 = NONE, 1 = FULL, 2 = INCREMENTAL.
    public func autoVacuumMode() -> Int64 {
        ((try? database.scalar("PRAGMA auto_vacuum")) as? Int64) ?? 0
    }

    @discardableResult
    public func ensureIncrementalAutoVacuum() -> Bool {
        if isIncrementalAutoVacuumActive { return true }
        // The auto_vacuum = INCREMENTAL requested at init only takes effect once
        // a full VACUUM rewrites the database into incremental mode.
        guard freeBytesAtDatabaseLocation() > databaseFileSizeBytes() else { return false }
        do {
            try database.vacuum()
        } catch {
            debugPrint("Auto-vacuum conversion VACUUM failed: \(error)")
        }
        isIncrementalAutoVacuumActive = autoVacuumMode() == 2
        return isIncrementalAutoVacuumActive
    }

    @discardableResult
    public func reclaimDiskSpace() -> Bool {
        if ensureIncrementalAutoVacuum() {
            do {
                try database.execute("PRAGMA incremental_vacuum;")
                return true
            } catch {
                debugPrint("Incremental vacuum failed: \(error)")
                return false
            }
        }
        do {
            try database.vacuum()
            return true
        } catch {
            debugPrint("VACUUM failed: \(error)")
            return false
        }
    }

    @discardableResult
    public func vacuum() -> Bool {
        reclaimDiskSpace()
    }

    @discardableResult
    public func compactDatabase() -> Bool {
        do {
            try database.vacuum()
            isIncrementalAutoVacuumActive = autoVacuumMode() == 2
            return true
        } catch {
            debugPrint("VACUUM failed: \(error)")
            return false
        }
    }

    public func databaseFileSizeBytes() -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func freeBytesAtDatabaseLocation() -> Int64 {
        let values = try? databaseURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    // MARK: - Row to Model Helpers

    public func albumFrom(row: Row, loadChildren: Bool = false) -> Album {
        let id = (try? row.get(albumId)) ?? ""
        let name = (try? row.get(albumName)) ?? ""
        let cover = try? row.get(albumCoverPhoto)
        let parentId = try? row.get(albumParentId)
        let dateCreated = Date(timeIntervalSince1970: (try? row.get(albumDateCreated)) ?? 0)
        let album = Album(id: id, name: name, coverPhoto: cover ?? nil,
                          parentAlbumID: parentId ?? nil, dateCreated: dateCreated)
        if loadChildren {
            album.childAlbums = fetchChildAlbums(forAlbumID: id)
            album.childPics = fetchChildPics(forAlbumID: id)
        }
        return album
    }

    public func albumCoverData(forAlbumWithID albumID: String) -> Data? {
        let query = albumsTable.filter(albumId == albumID).select(albumCoverPhoto)
        guard let row = try? database.pluck(query) else { return nil }
        return try? row.get(albumCoverPhoto)
    }

    public func batchAlbumCoverData(forAlbumIDs albumIDs: [String]) -> [String: Data] {
        guard !albumIDs.isEmpty else { return [:] }
        var result: [String: Data] = [:]
        for albumID in albumIDs {
            let query = albumsTable.filter(albumId == albumID).select(albumId, albumCoverPhoto)
            if let row = try? database.pluck(query),
               let data = try? row.get(albumCoverPhoto) {
                result[albumID] = data
            }
        }
        return result
    }

    public func picFrom(row: Row) -> Pic {
        let id = (try? row.get(picId)) ?? ""
        let name = (try? row.get(picName)) ?? ""
        let albumId = try? row.get(picAlbumId)
        let dateAdded = Date(timeIntervalSince1970: (try? row.get(picDateAdded)) ?? 0)
        let thumbData = try? row.get(picThumbnailData)
        let mediaTypeRaw = (try? row.get(picMediaType)) ?? 0
        let duration = try? row.get(picDuration)
        let filePath = try? row.get(picFilePath)
        let pinnedAt = (try? row.get(picPinnedAt)) ?? nil
        let dateDeleted = (try? row.get(picDateDeleted)) ?? nil
        let aspectRatio = (try? row.get(picThumbnailAspectRatio)) ?? nil
        let aiContent = (try? row.get(picAIContent)) ?? nil
        let pic = Pic(id: id, name: name,
                       containingAlbumID: albumId ?? nil,
                       dateAdded: dateAdded,
                       mediaType: MediaType(rawValue: mediaTypeRaw) ?? .pic,
                       duration: duration,
                       filePath: filePath)
        pic.thumbnailData = thumbData ?? nil
        pic.pinnedAt = pinnedAt.map { Date(timeIntervalSince1970: $0) }
        pic.dateDeleted = dateDeleted.map { Date(timeIntervalSince1970: $0) }
        pic.thumbnailAspectRatio = aspectRatio
        pic.aiContent = aiContent.flatMap(AIContentKind.init(rawValue:))
        return pic
    }

    public func fetchChildAlbums(forAlbumID id: String) -> [Album] {
        let query = albumsTable.filter(albumParentId == id)
        return (try? database.safeRows(query).map { albumFrom(row: $0, loadChildren: false) }) ?? []
    }

    public func fetchChildPics(forAlbumID id: String) -> [Pic] {
        let query = picsTable
            .filter(picAlbumId == id && picDateDeleted == nil)
            .select(picId, picName, picAlbumId,
                    picDateAdded, picThumbnailData,
                    picMediaType, picDuration, picFilePath, picPinnedAt)
        return (try? database.safeRows(query).map { picFrom(row: $0) }) ?? []
    }
}

extension Connection {
    // SQLite.swift's row sequences/statements conform to FailableIterator, whose
    // default IteratorProtocol `next()` force-tries the throwing `failableNext()`.
    // An error raised while *stepping* a statement (e.g. file I/O on the app-group
    // container being restricted while the app is backgrounded on iOS) is thrown
    // out of `failableNext()` and the `try!` traps the whole process — a `try?`
    // around `prepare(_:)` only guards statement compilation, not stepping.
    // Draining through `failableNext()` keeps the stepping error catchable.
    public func safeRows(_ query: QueryType) throws -> [Row] {
        let iterator = try prepareRowIterator(query)
        var rows: [Row] = []
        while let row = try iterator.failableNext() {
            rows.append(row)
        }
        return rows
    }

    public func safeRows(_ statement: String, _ bindings: [SQLite.Binding?] = []) throws -> [[SQLite.Binding?]] {
        let prepared = try prepare(statement, bindings)
        var rows: [[SQLite.Binding?]] = []
        while let row = try prepared.failableNext() {
            rows.append(row)
        }
        return rows
    }
}
