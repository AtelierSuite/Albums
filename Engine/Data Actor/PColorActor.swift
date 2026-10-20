import Foundation
@preconcurrency import SQLite

public actor PColorActor {

    nonisolated(unsafe) private static var _shared = PColorActor(collectionID: PicLibrary.persistedCurrentID)
    public static var shared: PColorActor { _shared }

    public static func switchLibrary(to collectionID: String) {
        _shared = PColorActor(collectionID: collectionID)
    }

    public static func instance(for collectionID: String) -> PColorActor {
        if collectionID == _shared.collectionID {
            return _shared
        }
        return PColorActor(collectionID: collectionID)
    }

    public nonisolated let collectionID: String

    public let database: Connection

    public let picColorsTable = Table("pic_colors")

    public let colorPicId = Expression<String>("pic_id")
    public let colorRed = Expression<Int>("red")
    public let colorGreen = Expression<Int>("green")
    public let colorBlue = Expression<Int>("blue")
    public let colorAccentRed = Expression<Int>("accent_red")
    public let colorAccentGreen = Expression<Int>("accent_green")
    public let colorAccentBlue = Expression<Int>("accent_blue")
    public let colorContrastingRed = Expression<Int>("contrasting_red")
    public let colorContrastingGreen = Expression<Int>("contrasting_green")
    public let colorContrastingBlue = Expression<Int>("contrasting_blue")

    public init(collectionID: String) {
        self.collectionID = collectionID
        let databaseFileName = "PColors.db"
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
            fatalError("Could not open SQLite color database: \(error)")
        }
        self.database = database
        do {
            try database.run(picColorsTable.create(ifNotExists: true) { table in
                table.column(colorPicId, primaryKey: true)
                table.column(colorRed)
                table.column(colorGreen)
                table.column(colorBlue)
                table.column(colorAccentRed, defaultValue: 0)
                table.column(colorAccentGreen, defaultValue: 0)
                table.column(colorAccentBlue, defaultValue: 0)
                table.column(colorContrastingRed, defaultValue: 0)
                table.column(colorContrastingGreen, defaultValue: 0)
                table.column(colorContrastingBlue, defaultValue: 0)
            })
            if DatabaseMigrator.migrationNeeded() {
                DatabaseMigrator.migrateColorDatabase(database, picColorsTable: picColorsTable)
            }
        } catch {
            debugPrint("Color database setup error: \(error)")
        }
    }

    // MARK: - Read

    public func cachedColor(forPicWithID picID: String) -> PicColors? {
        let query = picColorsTable.filter(colorPicId == picID)
        guard let row = try? database.pluck(query),
              let primary = try? RGBColor(red: row.get(colorRed),
                                          green: row.get(colorGreen),
                                          blue: row.get(colorBlue)),
              let accent = try? RGBColor(red: row.get(colorAccentRed),
                                         green: row.get(colorAccentGreen),
                                         blue: row.get(colorAccentBlue)),
              let contrasting = try? RGBColor(red: row.get(colorContrastingRed),
                                              green: row.get(colorContrastingGreen),
                                              blue: row.get(colorContrastingBlue)) else { return nil }
        return PicColors(primary: primary, accent: accent, contrasting: contrasting)
    }

    public func allCachedColors() -> [String: PicColors] {
        let query = picColorsTable.select(
            colorPicId, colorRed, colorGreen, colorBlue,
            colorAccentRed, colorAccentGreen, colorAccentBlue,
            colorContrastingRed, colorContrastingGreen, colorContrastingBlue
        )
        guard let rows = try? database.safeRows(query) else { return [:] }
        var result: [String: PicColors] = [:]
        for row in rows {
            guard let picID = try? row.get(colorPicId),
                  let primary = try? RGBColor(red: row.get(colorRed),
                                              green: row.get(colorGreen),
                                              blue: row.get(colorBlue)),
                  let accent = try? RGBColor(red: row.get(colorAccentRed),
                                             green: row.get(colorAccentGreen),
                                             blue: row.get(colorAccentBlue)),
                  let contrasting = try? RGBColor(red: row.get(colorContrastingRed),
                                                  green: row.get(colorContrastingGreen),
                                                  blue: row.get(colorContrastingBlue)) else { continue }
            result[picID] = PicColors(primary: primary, accent: accent, contrasting: contrasting)
        }
        return result
    }

    public func cachedColors(forPicIDs picIDs: [String]) -> [String: PicColors] {
        guard !picIDs.isEmpty else { return [:] }
        let placeholders = picIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        SELECT pic_id, red, green, blue, accent_red, accent_green, accent_blue, \
        contrasting_red, contrasting_green, contrasting_blue \
        FROM pic_colors WHERE pic_id IN (\(placeholders))
        """
        let bindings: [Binding?] = picIDs.map { $0 as Binding? }
        guard let stmt = try? database.safeRows(sql, bindings) else { return [:] }
        var result: [String: PicColors] = [:]
        for row in stmt {
            guard let picID = row[0] as? String else { continue }
            let values = (1...9).map { (row[$0] as? Int64).map(Int.init) ?? 0 }
            result[picID] = PicColors(
                primary: RGBColor(red: values[0], green: values[1], blue: values[2]),
                accent: RGBColor(red: values[3], green: values[4], blue: values[5]),
                contrasting: RGBColor(red: values[6], green: values[7], blue: values[8])
            )
        }
        return result
    }

    public func picIDsWithCachedColor() -> Set<String> {
        let query = picColorsTable.select(colorPicId)
        guard let rows = try? database.safeRows(query) else { return [] }
        var ids = Set<String>()
        for row in rows {
            if let picID = try? row.get(colorPicId) {
                ids.insert(picID)
            }
        }
        return ids
    }

    // MARK: - Write

    public func storeColor(_ colors: PicColors, forPicWithID picID: String) {
        _ = try? database.run(picColorsTable.insert(or: .replace, setters(for: picID, colors: colors)))
    }

    public func storeColors(_ colors: [(picID: String, colors: PicColors)]) {
        guard !colors.isEmpty else { return }
        _ = try? database.transaction {
            for entry in colors {
                _ = try? database.run(
                    picColorsTable.insert(or: .replace, setters(for: entry.picID, colors: entry.colors))
                )
            }
        }
    }

    private func setters(for picID: String, colors: PicColors) -> [Setter] {
        [
            colorPicId <- picID,
            colorRed <- colors.primary.red,
            colorGreen <- colors.primary.green,
            colorBlue <- colors.primary.blue,
            colorAccentRed <- colors.accent.red,
            colorAccentGreen <- colors.accent.green,
            colorAccentBlue <- colors.accent.blue,
            colorContrastingRed <- colors.contrasting.red,
            colorContrastingGreen <- colors.contrasting.green,
            colorContrastingBlue <- colors.contrasting.blue
        ]
    }

    // MARK: - Delete

    public func deleteColor(forPicWithID picID: String) {
        let query = picColorsTable.filter(colorPicId == picID)
        _ = try? database.run(query.delete())
    }

    public func deleteColors(forPicIDs picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let query = picColorsTable.filter(picIDs.contains(colorPicId))
        _ = try? database.run(query.delete())
    }

    public func deleteAllColors() {
        _ = try? database.run(picColorsTable.delete())
    }
}
