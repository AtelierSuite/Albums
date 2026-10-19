import Foundation
@preconcurrency import SQLite

public struct StoredFeaturePrint: Sendable {
    public let vector: [Float]
    public let labels: [String]
    public let visionRevision: Int

    public init(vector: [Float], labels: [String], visionRevision: Int) {
        self.vector = vector
        self.labels = labels
        self.visionRevision = visionRevision
    }
}

public actor FeaturePrintActor {

    nonisolated(unsafe) private static var _shared = FeaturePrintActor(collectionID: PicLibrary.defaultID)
    public static var shared: FeaturePrintActor { _shared }

    public static let currentPrintVersion = 1

    public static func switchLibrary(to collectionID: String) {
        _shared = FeaturePrintActor(collectionID: collectionID)
    }

    public static func instance(for collectionID: String) -> FeaturePrintActor {
        if collectionID == _shared.collectionID {
            return _shared
        }
        return FeaturePrintActor(collectionID: collectionID)
    }

    public nonisolated let collectionID: String

    public let database: Connection

    public let printsTable = Table("pic_feature_prints")

    public let printPicId = Expression<String>("pic_id")
    public let printFeatureData = Expression<Data>("feature_data")
    public let printLabels = Expression<String?>("labels")
    public let printVectorLen = Expression<Int>("vector_len")
    public let printVisionRevision = Expression<Int>("vision_revision")
    public let printVersion = Expression<Int>("print_version")

    public init(collectionID: String) {
        self.collectionID = collectionID
        let databaseFileName = "FeaturePrints.db"
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
            fatalError("Could not open SQLite feature print database: \(error)")
        }
        self.database = database
        do {
            try database.run(printsTable.create(ifNotExists: true) { table in
                table.column(printPicId, primaryKey: true)
                table.column(printFeatureData)
                table.column(printLabels)
                table.column(printVectorLen)
                table.column(printVisionRevision, defaultValue: 0)
                table.column(printVersion, defaultValue: 1)
            })
        } catch {
            debugPrint("Feature print database setup error: \(error)")
        }
    }

    // MARK: - Read

    public func cachedPrint(forPicWithID picID: String) -> StoredFeaturePrint? {
        let query = printsTable
            .filter(printPicId == picID && printVersion == Self.currentPrintVersion)
        guard let row = try? database.pluck(query) else { return nil }
        return stored(from: row)
    }

    public func cachedPrints(forPicIDs picIDs: [String]) -> [String: StoredFeaturePrint] {
        guard !picIDs.isEmpty else { return [:] }
        var result: [String: StoredFeaturePrint] = [:]
        let query = printsTable
            .filter(picIDs.contains(printPicId) && printVersion == Self.currentPrintVersion)
        guard let rows = try? database.safeRows(query) else { return [:] }
        for row in rows {
            guard let picID = try? row.get(printPicId),
                  let stored = stored(from: row) else { continue }
            result[picID] = stored
        }
        return result
    }

    public func picIDsWithCachedPrint() -> Set<String> {
        let query = printsTable
            .filter(printVersion == Self.currentPrintVersion)
            .select(printPicId)
        guard let rows = try? database.safeRows(query) else { return [] }
        var ids = Set<String>()
        for row in rows {
            if let picID = try? row.get(printPicId) {
                ids.insert(picID)
            }
        }
        return ids
    }

    private func stored(from row: Row) -> StoredFeaturePrint? {
        guard let data = try? row.get(printFeatureData) else { return nil }
        let vector = Self.floats(from: data)
        guard !vector.isEmpty else { return nil }
        let labels = (try? row.get(printLabels)).flatMap { $0 }.flatMap(Self.decodeLabels) ?? []
        let revision = (try? row.get(printVisionRevision)) ?? 0
        return StoredFeaturePrint(vector: vector, labels: labels, visionRevision: revision)
    }

    // MARK: - Write

    public func storePrint(_ vector: [Float], labels: [String], visionRevision: Int, forPicWithID picID: String) {
        _ = try? database.run(printsTable.insert(or: .replace,
            setters(for: picID, vector: vector, labels: labels, visionRevision: visionRevision)
        ))
    }

    public func storePrints(_ prints: [(picID: String, print: StoredFeaturePrint)]) {
        guard !prints.isEmpty else { return }
        _ = try? database.transaction {
            for entry in prints {
                _ = try? database.run(printsTable.insert(or: .replace,
                    setters(for: entry.picID,
                            vector: entry.print.vector,
                            labels: entry.print.labels,
                            visionRevision: entry.print.visionRevision)
                ))
            }
        }
    }

    private func setters(
        for picID: String, vector: [Float], labels: [String], visionRevision: Int
    ) -> [Setter] {
        [
            printPicId <- picID,
            printFeatureData <- Self.data(from: vector),
            printLabels <- Self.encodeLabels(labels),
            printVectorLen <- vector.count,
            printVisionRevision <- visionRevision,
            printVersion <- Self.currentPrintVersion
        ]
    }

    // MARK: - Delete

    public func deletePrint(forPicWithID picID: String) {
        let query = printsTable.filter(printPicId == picID)
        _ = try? database.run(query.delete())
    }

    public func deletePrints(forPicIDs picIDs: [String]) {
        guard !picIDs.isEmpty else { return }
        let query = printsTable.filter(picIDs.contains(printPicId))
        _ = try? database.run(query.delete())
    }

    public func deleteAllPrints() {
        _ = try? database.run(printsTable.delete())
    }

    // MARK: - Vector serialization

    public static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    public static func floats(from data: Data) -> [Float] {
        guard !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func encodeLabels(_ labels: [String]) -> String? {
        guard !labels.isEmpty, let data = try? JSONEncoder().encode(labels) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeLabels(_ string: String) -> [String]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
