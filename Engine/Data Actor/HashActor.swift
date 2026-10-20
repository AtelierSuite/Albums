import Foundation
@preconcurrency import SQLite

public actor HashActor {

    nonisolated(unsafe) private static var _shared = HashActor(collectionID: PicLibrary.persistedCurrentID)
    public static var shared: HashActor { _shared }

    /// Bumped to 2 when scanning switched from hashing originals to hashing thumbnails; older
    /// hashes are treated as uncached and recomputed.
    public static let currentHashVersion = 2

    public static func switchLibrary(to collectionID: String) {
        _shared = HashActor(collectionID: collectionID)
    }

    public static func instance(for collectionID: String) -> HashActor {
        if collectionID == _shared.collectionID {
            return _shared
        }
        return HashActor(collectionID: collectionID)
    }

    public nonisolated let collectionID: String

    public let database: Connection

    public let picHashesTable = Table("pic_hashes")

    public let hashPicId = Expression<String>("pic_id")
    public let hashValue = Expression<Int64>("dhash")
    public let hashVersion = Expression<Int>("hash_version")

    public init(collectionID: String) {
        self.collectionID = collectionID
        let databaseFileName = "Hashes.db"
        let fileManager = FileManager.default

        let databaseURL: URL
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            if collectionID == PicLibrary.defaultID {
                databaseURL = appGroupURL.appendingPathComponent(databaseFileName)
            } else {
                let folderURL = appGroupURL.appendingPathComponent(collectionID)
                try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                databaseURL = folderURL.appendingPathComponent(databaseFileName)
            }
        } else {
            fatalError()
        }

        let database: Connection
        do {
            database = try Connection(databaseURL.path)
        } catch {
            fatalError("Could not open SQLite hash database: \(error)")
        }
        self.database = database
        do {
            try database.run(picHashesTable.create(ifNotExists: true) { table in
                table.column(hashPicId, primaryKey: true)
                table.column(hashValue)
                table.column(hashVersion, defaultValue: 1)
            })
            if DatabaseMigrator.migrationNeeded() {
                DatabaseMigrator.migrateHashDatabase(database, picHashesTable: picHashesTable)
            }
        } catch {
            debugPrint("Hash database setup error: \(error)")
        }
    }

    // MARK: - Read

    public func cachedHash(forPicWithID picID: String) -> UInt64? {
        let query = picHashesTable.filter(hashPicId == picID).select(hashValue)
        guard let row = try? database.pluck(query),
              let value = try? row.get(hashValue) else { return nil }
        return UInt64(bitPattern: value)
    }

    public func allCachedHashes() -> [(String, UInt64)] {
        let query = picHashesTable
            .filter(hashVersion == Self.currentHashVersion)
            .select(hashPicId, hashValue)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { row in
            guard let picID = try? row.get(hashPicId),
                  let value = try? row.get(hashValue) else { return nil }
            return (picID, UInt64(bitPattern: value))
        }
    }

    public func picIDsWithCachedHash() -> Set<String> {
        let query = picHashesTable
            .filter(hashVersion == Self.currentHashVersion)
            .select(hashPicId)
        guard let rows = try? database.safeRows(query) else { return [] }
        var ids = Set<String>()
        for row in rows {
            if let picID = try? row.get(hashPicId) {
                ids.insert(picID)
            }
        }
        return ids
    }

    // MARK: - Write

    public func storeHash(_ hash: UInt64, forPicWithID picID: String) {
        let signedHash = Int64(bitPattern: hash)
        _ = try? database.run(picHashesTable.insert(or: .replace,
            hashPicId <- picID,
            hashValue <- signedHash,
            hashVersion <- Self.currentHashVersion
        ))
    }

    // MARK: - Delete

    public func deleteHash(forPicWithID picID: String) {
        let query = picHashesTable.filter(hashPicId == picID)
        _ = try? database.run(query.delete())
    }

    public func deleteHashes(forPicIDs picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let query = picHashesTable.filter(picIDs.contains(hashPicId))
        _ = try? database.run(query.delete())
    }

    public func deleteAllHashes() {
        _ = try? database.run(picHashesTable.delete())
    }
}
