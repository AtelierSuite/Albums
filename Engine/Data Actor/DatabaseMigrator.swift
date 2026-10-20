import Foundation
@preconcurrency import SQLite

public struct DatabaseMigrator: Sendable {

    private static let appGroupID = "group.com.tsubuzaki.IllustMate"
    private static let migratedVersionKey = "DatabaseMigratedVersion"
    private static let libraryV2CompletedKey = "LibraryV2MigrationsCompleted"

    public static func needsLibraryV2Migration() -> Bool {
        let defaults = UserDefaults(suiteName: appGroupID)
        return !(defaults?.bool(forKey: libraryV2CompletedKey) ?? false)
    }

    public static func markLibraryV2MigrationComplete() {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(true, forKey: libraryV2CompletedKey)
    }

    public static func migrationNeeded() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let defaults = UserDefaults(suiteName: appGroupID)
        let migratedVersion = defaults?.string(forKey: migratedVersionKey)
        return migratedVersion != currentVersion
    }

    public static func markMigrationComplete() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(currentVersion, forKey: migratedVersionKey)
    }

    // MARK: - Collection DB (albums + pics + preferences)

    public static func migrateCollectionDatabase(_ database: Connection,
                                                 albumsTable: Table,
                                                 picsTable: Table,
                                                 preferencesTable: Table) {
        let albumCoverPhoto = Expression<Data?>("cover_photo")
        let albumParentId = Expression<String?>("parent_album_id")
        let albumDateCreated = Expression<Double>("date_created")
        _ = try? database.run(albumsTable.addColumn(albumCoverPhoto))
        _ = try? database.run(albumsTable.addColumn(albumParentId))
        _ = try? database.run(albumsTable.addColumn(albumDateCreated, defaultValue: 0))

        let picName = Expression<String>("name")
        let picAlbumId = Expression<String?>("containing_album_id")
        let picDateAdded = Expression<Double>("date_added")
        let picThumbnailData = Expression<Data?>("thumbnail_data")
        let picMediaType = Expression<Int>("media_type")
        let picDuration = Expression<Double?>("duration")
        let picFilePath = Expression<String?>("file_path")
        _ = try? database.run(picsTable.addColumn(picName, defaultValue: ""))
        _ = try? database.run(picsTable.addColumn(picAlbumId))
        _ = try? database.run(picsTable.addColumn(picDateAdded, defaultValue: 0))
        _ = try? database.run(picsTable.addColumn(picThumbnailData))
        _ = try? database.run(picsTable.addColumn(picMediaType, defaultValue: 0))
        _ = try? database.run(picsTable.addColumn(picDuration))
        _ = try? database.run(picsTable.addColumn(picFilePath))

        let prefAlbumSort = Expression<String>("album_sort")
        let prefAlbumViewStyle = Expression<String>("album_view_style")
        let prefAlbumColumnCount = Expression<Int>("album_column_count")
        let prefPicSort = Expression<String>("pic_sort")
        let prefPicColumnCount = Expression<Int>("pic_column_count")
        let prefHideSectionHeaders = Expression<Bool>("hide_section_headers")
        _ = try? database.run(preferencesTable.addColumn(prefAlbumSort, defaultValue: "nameAscending"))
        _ = try? database.run(preferencesTable.addColumn(prefAlbumViewStyle, defaultValue: "grid"))
        _ = try? database.run(preferencesTable.addColumn(prefAlbumColumnCount, defaultValue: 4))
        _ = try? database.run(preferencesTable.addColumn(prefPicSort, defaultValue: "dateAddedDescending"))
        _ = try? database.run(preferencesTable.addColumn(prefPicColumnCount, defaultValue: 4))
        _ = try? database.run(preferencesTable.addColumn(prefHideSectionHeaders, defaultValue: false))
    }

    public static func stampSchemaVersionIfMigrated(_ database: Connection) {
        let hasDataColumn = ((try? database.safeRows("PRAGMA table_info(\"pics\")"))?
            .contains { ($0[1] as? String) == "data" }) ?? false
        guard !hasDataColumn,
              ((try? database.scalar("PRAGMA user_version") as? Int64) ?? 0) < DataActor.schemaVersion
        else { return }
        _ = try? database.execute("PRAGMA user_version = \(DataActor.schemaVersion);")
    }

    // MARK: - Pins

    public static func migratePinsColumn(_ database: Connection, picsTable: Table) {
        let existingColumns = (try? database.safeRows("PRAGMA table_info(\"pics\")"))?
            .compactMap { $0[1] as? String } ?? []
        guard !existingColumns.contains("pinned_at") else { return }
        _ = try? database.run(picsTable.addColumn(Expression<Double?>("pinned_at")))
    }

    // MARK: - Hashes DB

    public static func migrateHashDatabase(_ database: Connection, picHashesTable: Table) {
        let hashValue = Expression<Int64>("dhash")
        let hashVersion = Expression<Int>("hash_version")
        _ = try? database.run(picHashesTable.addColumn(hashValue, defaultValue: 0))
        _ = try? database.run(picHashesTable.addColumn(hashVersion, defaultValue: 1))
    }

    // MARK: - PColors DB

    public static func migrateColorDatabase(_ database: Connection, picColorsTable: Table) {
        let existingColumns = (try? database.safeRows("PRAGMA table_info(\"pic_colors\")"))?
            .compactMap { $0[1] as? String } ?? []

        let colorRed = Expression<Int>("red")
        let colorGreen = Expression<Int>("green")
        let colorBlue = Expression<Int>("blue")
        if !existingColumns.contains("red") {
            _ = try? database.run(picColorsTable.addColumn(colorRed, defaultValue: 0))
        }
        if !existingColumns.contains("green") {
            _ = try? database.run(picColorsTable.addColumn(colorGreen, defaultValue: 0))
        }
        if !existingColumns.contains("blue") {
            _ = try? database.run(picColorsTable.addColumn(colorBlue, defaultValue: 0))
        }

        guard !existingColumns.contains("accent_red") else { return }

        let accentRed = Expression<Int>("accent_red")
        let accentGreen = Expression<Int>("accent_green")
        let accentBlue = Expression<Int>("accent_blue")
        let contrastingRed = Expression<Int>("contrasting_red")
        let contrastingGreen = Expression<Int>("contrasting_green")
        let contrastingBlue = Expression<Int>("contrasting_blue")
        _ = try? database.run(picColorsTable.addColumn(accentRed, defaultValue: 0))
        _ = try? database.run(picColorsTable.addColumn(accentGreen, defaultValue: 0))
        _ = try? database.run(picColorsTable.addColumn(accentBlue, defaultValue: 0))
        _ = try? database.run(picColorsTable.addColumn(contrastingRed, defaultValue: 0))
        _ = try? database.run(picColorsTable.addColumn(contrastingGreen, defaultValue: 0))
        _ = try? database.run(picColorsTable.addColumn(contrastingBlue, defaultValue: 0))

        _ = try? database.run(picColorsTable.delete())
    }

    // MARK: - Cover Cache DB

    public static func migrateCoverCacheDatabase(_ database: Connection, coverCacheTable: Table) {
        let cacheVersionKey = Expression<String>("version_key")
        let cachePrimary = Expression<Data?>("primary_data")
        let cacheSecondary = Expression<Data?>("secondary_data")
        let cacheTertiary = Expression<Data?>("tertiary_data")
        _ = try? database.run(coverCacheTable.addColumn(cacheVersionKey, defaultValue: ""))
        _ = try? database.run(coverCacheTable.addColumn(cachePrimary))
        _ = try? database.run(coverCacheTable.addColumn(cacheSecondary))
        _ = try? database.run(coverCacheTable.addColumn(cacheTertiary))
    }

    // MARK: - Libraries DB

    public static func migrateLibrariesDatabase(_ database: Connection, librariesTable: Table) {
        let libraryName = Expression<String>("name")
        _ = try? database.run(librariesTable.addColumn(libraryName, defaultValue: ""))
    }
}
