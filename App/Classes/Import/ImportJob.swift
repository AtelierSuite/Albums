import Foundation

nonisolated struct ImportJob: Codable, Sendable, Identifiable, Hashable {

    let id: UUID
    let dateCreated: Date
    let libraryID: String
    let destinationAlbumID: String?
    let destinationAlbumName: String?
    var items: [ImportItem]
    var createdAlbumIDs: [String]

    init(
        libraryID: String,
        destinationAlbumID: String?,
        destinationAlbumName: String?,
        items: [ImportItem] = [],
        createdAlbumIDs: [String] = []
    ) {
        self.id = UUID()
        self.dateCreated = .now
        self.libraryID = libraryID
        self.destinationAlbumID = destinationAlbumID
        self.destinationAlbumName = destinationAlbumName
        self.items = items
        self.createdAlbumIDs = createdAlbumIDs
    }

    var affectedAlbumIDs: Set<String> {
        var ids = Set(items.compactMap(\.albumID))
        if let destinationAlbumID {
            ids.insert(destinationAlbumID)
        }
        return ids
    }
}

nonisolated struct ImportItem: Codable, Sendable, Hashable {

    enum Source: Codable, Sendable, Hashable {
        case photosAsset(localIdentifier: String, isVideo: Bool)
        case stagedFile(name: String, originalFilename: String)
    }

    let source: Source
    let albumID: String?
    var dateAdded: Date?
}

nonisolated struct ImportJobProgress: Codable, Sendable {
    var nextIndex: Int = 0
    var importedPicIDs: [String] = []
}

nonisolated struct ImportJobResult: Sendable {
    let jobID: UUID
    let importedCount: Int
    let wasCancelled: Bool
}
