import Foundation
@preconcurrency import SQLite

public enum ImageMigrationPhase: Sendable {
    case preparing
    case copying
    case verifying
    case reclaiming
}

public struct ImageMigrationProgress: Sendable {
    public let phase: ImageMigrationPhase
    public let completed: Int
    public let total: Int
    public let latestThumbnail: Data?

    public init(phase: ImageMigrationPhase, completed: Int, total: Int, latestThumbnail: Data? = nil) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.latestThumbnail = latestThumbnail
    }
}

extension DataActor {

    public static let libraryV2MigrationName = "LibraryV2"
    public static let schemaVersion: Int64 = 2

    public func needsImageMigration() -> Bool {
        guard dataColumnExists() else { return false }
        return nonEmptyImageBlobCount() > 0
    }

    public func isLibraryV2MigrationComplete() -> Bool {
        guard !needsImageMigration() else { return false }
        markLibraryV2MigrationComplete()
        return true
    }

    public func markLibraryV2MigrationComplete() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        _ = try? database.run(migrationsTable.insert(or: .replace,
            migrationName <- Self.libraryV2MigrationName,
            migrationAppVersion <- version,
            migrationCompleted <- true
        ))
    }

    public func migrateImageBlobsToFiles(
        progress: @escaping @MainActor (ImageMigrationProgress) -> Void
    ) async {
        guard dataColumnExists() else {
            markSchemaVersionCurrent()
            return
        }
        let pending = pendingMigrationIDs()
        let total = pending.count
        guard total > 0 else {
            dropDataColumnIfMigrated()
            compactDatabase()
            return
        }
        await progress(ImageMigrationProgress(phase: .copying, completed: 0,
                                              total: total, latestThumbnail: nil))

        var copied = 0
        for id in pending {
            copyBlobToFile(id: id)
            copied += 1
            await progress(ImageMigrationProgress(phase: .copying, completed: copied,
                                                  total: total,
                                                  latestThumbnail: thumbnailData(forPicWithID: id)))
        }
        var verifiedIDs: [String] = []
        var verified = 0
        for id in pending {
            if !blobIsEmpty(id: id) {
                if verifyMigratedFile(id: id) {
                    verifiedIDs.append(id)
                } else {
                    revertMigratedFile(id: id)
                }
            }
            verified += 1
            await progress(ImageMigrationProgress(phase: .verifying, completed: verified,
                                                  total: total,
                                                  latestThumbnail: thumbnailData(forPicWithID: id)))
        }
        for id in verifiedIDs {
            zeroBlob(id: id)
        }
        await progress(ImageMigrationProgress(phase: .reclaiming, completed: 0,
                                              total: 0, latestThumbnail: nil))
        dropDataColumnIfMigrated()
        if !compactDatabase() {
            debugPrint("Image migration: final disk space reclamation freed no space")
        }
    }

    // MARK: - Schema

    public func dataColumnExists() -> Bool {
        guard let rows = try? database.safeRows("PRAGMA table_info(\"pics\")") else { return false }
        for row in rows where (row[1] as? String) == "data" { return true }
        return false
    }

    public func dropDataColumnIfMigrated() {
        guard dataColumnExists() else {
            markSchemaVersionCurrent()
            return
        }
        let remaining = (try? database.scalar(
            "SELECT COUNT(*) FROM \"pics\" WHERE \"data\" IS NOT NULL AND length(\"data\") > 0"
        ) as? Int64) ?? 1
        guard remaining == 0 else { return }
        do {
            try database.execute("ALTER TABLE \"pics\" DROP COLUMN \"data\"")
        } catch {
            debugPrint("Failed to drop data column: \(error)")
            return
        }
        markSchemaVersionCurrent()
    }

    private func markSchemaVersionCurrent() {
        let current = (try? database.scalar("PRAGMA user_version") as? Int64) ?? 0
        guard current < Self.schemaVersion else { return }
        _ = try? database.execute("PRAGMA user_version = \(Self.schemaVersion);")
    }

    private func nonEmptyImageBlobCount() -> Int64 {
        (try? database.scalar(
            "SELECT COUNT(*) FROM \"pics\" WHERE \"media_type\" = \(MediaType.pic.rawValue) " +
            "AND \"data\" IS NOT NULL AND length(\"data\") > 0"
        ) as? Int64) ?? 0
    }

    // MARK: - Helpers

    private func pendingMigrationIDs() -> [String] {
        guard dataColumnExists() else { return [] }
        let sql = "SELECT \"id\" FROM \"pics\" WHERE \"media_type\" = \(MediaType.pic.rawValue) " +
                  "AND \"data\" IS NOT NULL AND length(\"data\") > 0"
        guard let statement = try? database.safeRows(sql) else { return [] }
        var ids: [String] = []
        for row in statement {
            if let id = row[0] as? String { ids.append(id) }
        }
        return ids
    }

    private func blobIsEmpty(id: String) -> Bool {
        guard let blob = rawBlobData(forPicWithID: id) else { return true }
        return blob.isEmpty
    }

    private func zeroBlob(id: String) {
        do {
            try database.run(picsTable.filter(picId == id).update(picData <- Data()))
        } catch {
            debugPrint("Failed to clear migrated blob for \(id): \(error)")
        }
    }

    private func copyBlobToFile(id: String) {
        guard let blob = rawBlobData(forPicWithID: id), !blob.isEmpty,
              let relativePath = saveImageFile(blob, id: id) else { return }
        _ = try? database.run(picsTable.filter(picId == id).update(picFilePath <- relativePath))
    }

    private func revertMigratedFile(id: String) {
        let query = picsTable.filter(picId == id).select(picFilePath)
        if let row = try? database.pluck(query),
           let path = (try? row.get(picFilePath)) ?? nil {
            deleteImageFile(atRelativePath: path)
        }
        _ = try? database.run(picsTable.filter(picId == id).update(picFilePath <- nil))
    }

    private func verifyMigratedFile(id: String) -> Bool {
        guard let blob = rawBlobData(forPicWithID: id) else { return false }
        let query = picsTable.filter(picId == id).select(picFilePath)
        guard let row = try? database.pluck(query),
              let path = try? row.get(picFilePath),
              let fileData = try? Data(contentsOf: imageFileURL(forRelativePath: path)) else {
            return false
        }
        return fileData == blob
    }

}

extension DataActor {
    public func createImageBlobPic(_ name: String, data: Data,
                                   inAlbumWithID albumID: String? = nil, dateAdded: Date? = nil) {
        _ = try? database.execute("ALTER TABLE \"pics\" ADD COLUMN \"data\" BLOB")
        let id = UUID().uuidString
        let now = dateAdded ?? Date.now
        _ = try? database.run(picsTable.insert(
            picId <- id,
            picName <- name,
            picAlbumId <- albumID,
            picDateAdded <- now.timeIntervalSince1970,
            picData <- data,
            picThumbnailData <- Pic.makeThumbnail(data),
            picMediaType <- MediaType.pic.rawValue
        ))
    }
}
