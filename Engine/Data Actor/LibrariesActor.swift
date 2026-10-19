import Foundation
@preconcurrency import SQLite

public actor LibrariesActor {

    public static let shared = LibrariesActor()

    public let database: Connection

    public let librariesTable = Table("collections")

    public let libraryId = Expression<String>("id")
    public let libraryName = Expression<String>("name")

    public let libraryDirty = Expression<Bool>("dirty")
    public let libraryLastModified = Expression<Double>("last_modified")
    public let libraryCKSystemFields = Expression<Data?>("ck_system_fields")
    public let librarySyncEnabled = Expression<Bool>("sync_enabled")
    public let libraryStorageMode = Expression<String>("storage_mode")
    public let libraryMigratedV2 = Expression<Bool>("migrated_v2")
    public let libraryCoverPicIDs = Expression<String>("cover_pic_ids")
    public let tombstonesTable = Table("library_tombstones")
    public let tombstoneId = Expression<String>("id")
    public let tombstoneDeletedAt = Expression<Double>("deleted_at")

    public init() {
        let databaseFileName = "Libraries.db"
        let fileManager = FileManager.default

        let databaseURL: URL
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            databaseURL = appGroupURL.appendingPathComponent(databaseFileName)
        } else {
            fatalError()
        }

        let database: Connection
        do {
            database = try Connection(databaseURL.path)
        } catch {
            fatalError("Could not open SQLite libraries database: \(error)")
        }
        self.database = database
        do {
            try database.run(librariesTable.create(ifNotExists: true) { table in
                table.column(libraryId, primaryKey: true)
                table.column(libraryName)
            })
            if DatabaseMigrator.migrationNeeded() {
                DatabaseMigrator.migrateLibrariesDatabase(database, librariesTable: librariesTable)
            }
            let defaultExists = try database.scalar(
                librariesTable.filter(libraryId == PicLibrary.defaultID).count
            ) > 0
            if !defaultExists {
                _ = try database.run(librariesTable.insert(
                    libraryId <- PicLibrary.defaultID,
                    libraryName <- ""
                ))
            }
            _ = try? database.run(librariesTable.addColumn(libraryDirty, defaultValue: true))
            _ = try? database.run(librariesTable.addColumn(libraryLastModified, defaultValue: 0))
            _ = try? database.run(librariesTable.addColumn(libraryCKSystemFields))
            _ = try? database.run(librariesTable.addColumn(librarySyncEnabled, defaultValue: false))
            _ = try? database.run(librariesTable.addColumn(libraryStorageMode,
                                                           defaultValue: StorageMode.optimize.rawValue))
            _ = try? database.run(librariesTable.addColumn(libraryMigratedV2, defaultValue: false))
            _ = try? database.run(librariesTable.addColumn(libraryCoverPicIDs, defaultValue: ""))
            try database.run(tombstonesTable.create(ifNotExists: true) { table in
                table.column(tombstoneId, primaryKey: true)
                table.column(tombstoneDeletedAt, defaultValue: 0)
            })
        } catch {
            debugPrint("Libraries database setup error: \(error)")
        }
    }

    // MARK: - Read

    public func allLibraries() -> [PicLibrary] {
        let query = librariesTable.order(libraryId.desc)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { row in
            guard let id = try? row.get(libraryId),
                  let name = try? row.get(libraryName) else { return nil }
            return PicLibrary(id: id, name: name,
                              syncEnabled: (try? row.get(librarySyncEnabled)) ?? false)
        }
    }

    public func library(for id: String) -> PicLibrary? {
        let query = librariesTable.filter(libraryId == id)
        guard let row = try? database.pluck(query),
              let id = try? row.get(libraryId),
              let name = try? row.get(libraryName) else { return nil }
        return PicLibrary(id: id, name: name,
                          syncEnabled: (try? row.get(librarySyncEnabled)) ?? false)
    }

    // MARK: - Write

    public func createLibrary(name: String) -> PicLibrary {
        let id = PicLibrary.newID()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        let fileManager = FileManager.default
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            let folderURL = appGroupURL.appendingPathComponent(id)
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        _ = try? database.run(librariesTable.insert(
            libraryId <- id,
            libraryName <- trimmedName,
            libraryDirty <- true,
            libraryLastModified <- Date.now.timeIntervalSince1970
        ))
        return PicLibrary(id: id, name: trimmedName)
    }

    public func renameLibrary(withID id: String, to newName: String) {
        let query = librariesTable.filter(libraryId == id)
        _ = try? database.run(query.update(
            libraryName <- newName.trimmingCharacters(in: .whitespaces),
            libraryDirty <- true,
            libraryLastModified <- Date.now.timeIntervalSince1970
        ))
    }

    public func coverPicIDs(forID id: String) -> [String] {
        guard let row = try? database.pluck(librariesTable.filter(libraryId == id)),
              let joined = try? row.get(libraryCoverPicIDs) else { return [] }
        return joined.split(separator: ",").map(String.init)
    }

    public func setCoverPicIDs(_ picIDs: [String], forID id: String) {
        _ = try? database.run(librariesTable.filter(libraryId == id)
            .update(libraryCoverPicIDs <- picIDs.joined(separator: ",")))
    }

    // MARK: - Delete

    public func deleteLibrary(withID id: String) {
        guard id != PicLibrary.defaultID else { return }

        _ = try? database.run(tombstonesTable.insert(or: .replace,
            tombstoneId <- id,
            tombstoneDeletedAt <- Date.now.timeIntervalSince1970
        ))
        let query = librariesTable.filter(libraryId == id)
        _ = try? database.run(query.delete())

        let fileManager = FileManager.default
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            let folderURL = appGroupURL.appendingPathComponent(id)
            try? fileManager.removeItem(at: folderURL)
        }
    }
}

extension LibrariesActor {

    // MARK: - Sync bookkeeping (registry, excludes the default library)

    public func dirtyLibraryIDs() -> [String] {
        let query = librariesTable
            .filter(libraryDirty == true && librarySyncEnabled == true
                    && libraryMigratedV2 == true && libraryId != PicLibrary.defaultID)
            .select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func unsyncedLibraryIDs() -> [String] {
        let query = librariesTable
            .filter(libraryCKSystemFields == nil && librarySyncEnabled == true
                    && libraryMigratedV2 == true && libraryId != PicLibrary.defaultID
                    && libraryName != "")
            .select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func confirmedSyncedLibraryIDs() -> [String] {
        let query = librariesTable
            .filter(librarySyncEnabled == true && libraryCKSystemFields != nil
                    && libraryId != PicLibrary.defaultID)
            .select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func syncEnabledLibraryIDs() -> [String] {
        let query = librariesTable
            .filter(librarySyncEnabled == true && libraryMigratedV2 == true)
            .select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func allLibraryIDs() -> [String] {
        (try? database.safeRows(librariesTable.select(libraryId)).map { $0[libraryId] }) ?? []
    }

    public func unmigratedLibraryIDs() -> [String] {
        let query = librariesTable.filter(libraryMigratedV2 == false).select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func setLibraryMigrated(_ migrated: Bool, forID id: String) {
        _ = try? database.run(librariesTable.filter(libraryId == id)
            .update(libraryMigratedV2 <- migrated))
    }

    public func storageMode(forID id: String) -> String {
        guard let row = try? database.pluck(librariesTable.filter(libraryId == id)) else {
            return StorageMode.optimize.rawValue
        }
        return (try? row.get(libraryStorageMode)) ?? StorageMode.optimize.rawValue
    }

    public func setStorageMode(_ mode: String, forID id: String) {
        _ = try? database.run(librariesTable.filter(libraryId == id).update(libraryStorageMode <- mode))
    }

    public func downloadAllLibraryIDs() -> [String] {
        let query = librariesTable
            .filter(librarySyncEnabled == true && libraryMigratedV2 == true
                    && libraryStorageMode == StorageMode.downloadAll.rawValue)
            .select(libraryId)
        return (try? database.safeRows(query).map { $0[libraryId] }) ?? []
    }

    public func isSyncEnabled(id: String) -> Bool {
        guard let row = try? database.pluck(librariesTable.filter(libraryId == id)) else { return false }
        return (try? row.get(librarySyncEnabled)) ?? false
    }

    public func setSyncEnabled(_ enabled: Bool, forID id: String) {
        let query = librariesTable.filter(libraryId == id)
        if enabled {
            _ = try? database.run(query.update(
                librarySyncEnabled <- true,
                libraryDirty <- true,
                libraryLastModified <- Date.now.timeIntervalSince1970
            ))
        } else {
            _ = try? database.run(query.update(librarySyncEnabled <- false))
        }
    }

    public func pendingLibraryTombstones() -> [String] {
        (try? database.safeRows(tombstonesTable).map { $0[tombstoneId] }) ?? []
    }

    public func removeLibraryTombstone(id: String) {
        _ = try? database.run(tombstonesTable.filter(tombstoneId == id).delete())
    }

    public func librarySyncSnapshot(forID id: String) -> LibrarySyncSnapshot? {
        guard let row = try? database.pluck(librariesTable.filter(libraryId == id)) else { return nil }
        return LibrarySyncSnapshot(
            id: id,
            name: (try? row.get(libraryName)) ?? "",
            systemFields: try? row.get(libraryCKSystemFields),
            lastModified: (try? row.get(libraryLastModified)) ?? 0
        )
    }

    public func markLibrarySynced(id: String, systemFields: Data?) {
        _ = try? database.run(librariesTable.filter(libraryId == id)
            .update(libraryDirty <- false, libraryCKSystemFields <- systemFields))
    }

    public func insertRemoteLibraryStub(id: String) {
        guard id != PicLibrary.defaultID else { return }
        ensureFolder(for: id)
        _ = try? database.run(librariesTable.insert(or: .ignore,
            libraryId <- id,
            libraryName <- "",
            libraryDirty <- false,
            librarySyncEnabled <- true,
            libraryMigratedV2 <- true,
            libraryLastModified <- 0
        ))
    }

    public func applyRemoteLibrary(_ snapshot: LibrarySyncSnapshot) {
        guard snapshot.id != PicLibrary.defaultID else { return }
        ensureFolder(for: snapshot.id)
        let exists = ((try? database.scalar(librariesTable.filter(libraryId == snapshot.id).count)) ?? 0) > 0
        if exists {
            _ = try? database.run(librariesTable.filter(libraryId == snapshot.id).update(
                libraryName <- snapshot.name,
                libraryDirty <- false,
                libraryCKSystemFields <- snapshot.systemFields,
                libraryLastModified <- snapshot.lastModified
            ))
        } else {
            _ = try? database.run(librariesTable.insert(or: .replace,
                libraryId <- snapshot.id,
                libraryName <- snapshot.name,
                libraryDirty <- false,
                librarySyncEnabled <- true,
                libraryMigratedV2 <- true,
                libraryCKSystemFields <- snapshot.systemFields,
                libraryLastModified <- snapshot.lastModified
            ))
        }
    }

    public func removeLibraryForRemoteDelete(id: String) {
        guard id != PicLibrary.defaultID else { return }
        _ = try? database.run(librariesTable.filter(libraryId == id).delete())
        let fileManager = FileManager.default
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            try? fileManager.removeItem(at: appGroupURL.appendingPathComponent(id))
        }
    }

    private func ensureFolder(for id: String) {
        let fileManager = FileManager.default
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) {
            let folderURL = appGroupURL.appendingPathComponent(id)
            if !fileManager.fileExists(atPath: folderURL.path) {
                try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        }
    }
}
