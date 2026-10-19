import Foundation
@preconcurrency import SQLite

public struct EntityPrototype: Codable, Sendable {
    public var centroid: [Float]
    public var medoidPicID: String
    public var memberCount: Int
    public var labels: [String]

    public init(centroid: [Float], medoidPicID: String, memberCount: Int, labels: [String]) {
        self.centroid = centroid
        self.medoidPicID = medoidPicID
        self.memberCount = memberCount
        self.labels = labels
    }
}

public struct AlbumModel: Codable, Sendable {
    public var prototypes: [EntityPrototype]
    public var memberCount: Int
    public var limitedData: Bool

    public init(prototypes: [EntityPrototype], memberCount: Int, limitedData: Bool) {
        self.prototypes = prototypes
        self.memberCount = memberCount
        self.limitedData = limitedData
    }
}

public actor AlbumModelActor {

    nonisolated(unsafe) private static var _shared = AlbumModelActor(collectionID: PicLibrary.defaultID)
    public static var shared: AlbumModelActor { _shared }

    public static let currentPrintVersion = FeaturePrintActor.currentPrintVersion

    public static func switchLibrary(to collectionID: String) {
        _shared = AlbumModelActor(collectionID: collectionID)
    }

    public static func instance(for collectionID: String) -> AlbumModelActor {
        if collectionID == _shared.collectionID {
            return _shared
        }
        return AlbumModelActor(collectionID: collectionID)
    }

    public nonisolated let collectionID: String

    public let database: Connection

    public let modelsTable = Table("album_models")

    public let modelAlbumId = Expression<String>("album_id")
    public let modelData = Expression<Data>("model_data")
    public let modelMemberSignature = Expression<String>("member_signature")
    public let modelPrintVersion = Expression<Int>("print_version")

    public init(collectionID: String) {
        self.collectionID = collectionID
        let databaseFileName = "AlbumModels.db"
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
            fatalError("Could not open SQLite album model database: \(error)")
        }
        self.database = database
        do {
            try database.run(modelsTable.create(ifNotExists: true) { table in
                table.column(modelAlbumId, primaryKey: true)
                table.column(modelData)
                table.column(modelMemberSignature)
                table.column(modelPrintVersion, defaultValue: 1)
            })
        } catch {
            debugPrint("Album model database setup error: \(error)")
        }
    }

    // MARK: - Read

    public func cachedModel(forAlbumWithID albumID: String) -> (model: AlbumModel, signature: String)? {
        let query = modelsTable
            .filter(modelAlbumId == albumID && modelPrintVersion == Self.currentPrintVersion)
        guard let row = try? database.pluck(query),
              let data = try? row.get(modelData),
              let model = try? JSONDecoder().decode(AlbumModel.self, from: data),
              let signature = try? row.get(modelMemberSignature) else { return nil }
        return (model, signature)
    }

    // MARK: - Write

    public func storeModel(_ model: AlbumModel, signature: String, forAlbumWithID albumID: String) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        _ = try? database.run(modelsTable.insert(or: .replace,
            modelAlbumId <- albumID,
            modelData <- data,
            modelMemberSignature <- signature,
            modelPrintVersion <- Self.currentPrintVersion
        ))
    }

    // MARK: - Delete

    public func deleteModel(forAlbumWithID albumID: String) {
        let query = modelsTable.filter(modelAlbumId == albumID)
        _ = try? database.run(query.delete())
    }

    public func deleteModels(forAlbumIDs albumIDs: [String]) {
        guard !albumIDs.isEmpty else { return }
        let query = modelsTable.filter(albumIDs.contains(modelAlbumId))
        _ = try? database.run(query.delete())
    }

    public func deleteAllModels() {
        _ = try? database.run(modelsTable.delete())
    }
}
