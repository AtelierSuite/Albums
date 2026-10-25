import CoreSpotlight
import Engine
import Foundation
import UniformTypeIdentifiers

struct SpotlightItemID: Hashable, Sendable {

    enum Kind: String, Sendable {
        case album
        case pic
    }

    let kind: Kind
    let libraryID: String
    let itemID: String

    init(kind: Kind, libraryID: String, itemID: String) {
        self.kind = kind
        self.libraryID = libraryID
        self.itemID = itemID
    }

    init?(_ identifier: String) {
        let parts = identifier.split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.count == 3, let kind = Kind(rawValue: parts[0]) else { return nil }
        self.init(kind: kind, libraryID: parts[1], itemID: parts[2])
    }

    var identifier: String { "\(kind.rawValue)/\(libraryID)/\(itemID)" }

    static func domain(forLibraryID libraryID: String) -> String { "library.\(libraryID)" }
}

private struct SpotlightEntry: Sendable {
    let id: SpotlightItemID
    let signature: UInt64
    let name: String
    let context: String
    let contentType: UTType
    let date: Date
    let duration: Double?
    var coverPicID: String?
}

actor SpotlightIndexer {

    static let shared = SpotlightIndexer()

    private static let schemaVersion = "1"
    private static let batchSize = 200
    private static let deleteBatchSize = 1000
    private static let checkpointInterval = 10

    private var pendingLibraryIDs: Set<String> = []
    private var needsFullReconcile = false
    private var isReconciling = false
    private var debounceTask: Task<Void, Never>?

    static var isIndexingAllowed: Bool {
        !(UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")?.bool(forKey: "AppLockEnabled") ?? false)
    }

    func scheduleReconcile(libraryIDs: [String]? = nil, after delay: Duration = .seconds(2)) {
        if let libraryIDs {
            pendingLibraryIDs.formUnion(libraryIDs)
        } else {
            needsFullReconcile = true
        }
        debounceTask?.cancel()
        debounceTask = Task(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            Task(priority: .utility) { await self.drain() }
        }
    }

    private func drain() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        while needsFullReconcile || !pendingLibraryIDs.isEmpty {
            let requestedIDs: Set<String>? = needsFullReconcile ? nil : pendingLibraryIDs
            needsFullReconcile = false
            pendingLibraryIDs.removeAll()
            await reconcile(requestedIDs)
        }
    }

    private func reconcile(_ requestedIDs: Set<String>?) async {
        guard Self.isIndexingAllowed else {
            await purgeAll()
            return
        }
        if let directory = Self.stateDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let libraries = await LibrariesActor.shared.allLibraries()
        let liveIDs = Set(libraries.map(\.id))
        let removedIDs = Self.storedLibraryIDs().subtracting(liveIDs)
        if !removedIDs.isEmpty {
            await Self.deleteDomains(removedIDs.map(SpotlightItemID.domain(forLibraryID:)))
            removedIDs.forEach(Self.removeState(forLibraryID:))
        }
        for library in libraries where requestedIDs?.contains(library.id) ?? true {
            guard Self.isIndexingAllowed else { return }
            await reconcileLibrary(library)
        }
    }

    private func purgeAll() async {
        guard let directory = Self.stateDirectory,
              FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try await CSSearchableIndex.default().deleteAllSearchableItems()
            try? FileManager.default.removeItem(at: directory)
        } catch {
            debugPrint("Spotlight purge failed: \(error)")
        }
    }

    private func reconcileLibrary(_ library: PicLibrary) async {
        guard Self.databaseExists(forLibraryID: library.id),
              await LibrariesActor.shared.library(for: library.id) != nil else { return }
        let dataActor = DataActor.instance(for: library.id)
        let entries = Self.entries(albums: await dataActor.spotlightAlbumRows(),
                                   pics: await dataActor.spotlightPicRows(),
                                   in: library)

        let storedState = Self.loadState(forLibraryID: library.id)
        if storedState == nil {
            await Self.deleteDomains([SpotlightItemID.domain(forLibraryID: library.id)])
        }
        var state = storedState ?? [:]
        let liveIdentifiers = Set(entries.map(\.id.identifier))
        let staleIdentifiers = state.keys.filter { !liveIdentifiers.contains($0) }
        for batch in staleIdentifiers.chunked(into: Self.deleteBatchSize) {
            guard await Self.deleteItems(batch) else { return }
            batch.forEach { state.removeValue(forKey: $0) }
        }

        let changed = entries.filter { state[$0.id.identifier] != $0.signature }
        for (offset, batch) in changed.chunked(into: Self.batchSize).enumerated() {
            guard Self.isIndexingAllowed else { return }
            let thumbnails = await thumbnails(for: batch, in: dataActor)
            guard await Self.index(batch, thumbnails: thumbnails) else { break }
            batch.forEach { state[$0.id.identifier] = $0.signature }
            if (offset + 1).isMultiple(of: Self.checkpointInterval) {
                Self.saveState(state, forLibraryID: library.id)
            }
        }
        guard Self.isIndexingAllowed else { return }
        Self.saveState(state, forLibraryID: library.id)
    }

    private static func entries(albums: [SpotlightAlbumRow], pics: [SpotlightPicRow],
                                in library: PicLibrary) -> [SpotlightEntry] {
        let libraryName = displayName(for: library)
        let albumNames = Dictionary(albums.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func context(albumID: String?) -> String {
            [albumID.flatMap { albumNames[$0] }, libraryName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        let albumEntries = albums.map { album in
            let itemContext = context(albumID: album.parentAlbumID)
            let coverPicID = album.coverSize == 0 ? album.newestPicID : nil
            return SpotlightEntry(
                id: SpotlightItemID(kind: .album, libraryID: library.id, itemID: album.id),
                signature: signature([album.name, itemContext, String(album.coverSize), coverPicID ?? ""]),
                name: album.name, context: itemContext, contentType: .folder,
                date: album.dateCreated, duration: nil, coverPicID: coverPicID
            )
        }
        let picEntries = pics.map { pic in
            let itemContext = context(albumID: pic.albumID)
            return SpotlightEntry(
                id: SpotlightItemID(kind: .pic, libraryID: library.id, itemID: pic.id),
                signature: signature([pic.name, itemContext, String(pic.thumbnailSize),
                                      String(pic.mediaType.rawValue)]),
                name: pic.name, context: itemContext,
                contentType: pic.mediaType == .video ? .movie : .image,
                date: pic.dateAdded, duration: pic.duration
            )
        }
        return albumEntries + picEntries
    }

    private func thumbnails(for batch: [SpotlightEntry], in dataActor: DataActor) async -> [String: Data] {
        let picIDs = batch.filter { $0.id.kind == .pic }.map(\.id.itemID)
        let albums = batch.filter { $0.id.kind == .album }
        let picThumbnails = await dataActor.spotlightThumbnails(forPicIDs: picIDs + albums.compactMap(\.coverPicID))
        var result = picThumbnails
        if !albums.isEmpty {
            let covers = await dataActor.batchAlbumCoverData(forAlbumIDs: albums.map(\.id.itemID))
            for album in albums {
                result[album.id.itemID] = covers[album.id.itemID] ?? album.coverPicID.flatMap { picThumbnails[$0] }
            }
        }
        return result
    }

    // MARK: - Core Spotlight

    private static func index(_ entries: [SpotlightEntry], thumbnails: [String: Data]) async -> Bool {
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: entry.contentType)
            attributes.title = entry.name
            attributes.displayName = entry.name
            attributes.contentDescription = entry.context
            attributes.thumbnailData = thumbnails[entry.id.itemID]
            attributes.addedDate = entry.date
            attributes.contentCreationDate = entry.date
            if let duration = entry.duration {
                attributes.duration = NSNumber(value: duration)
            }
            let item = CSSearchableItem(
                uniqueIdentifier: entry.id.identifier,
                domainIdentifier: SpotlightItemID.domain(forLibraryID: entry.id.libraryID),
                attributeSet: attributes
            )
            // Items expire after about a month unless an explicit expiration date is set.
            item.expirationDate = .distantFuture
            return item
        }
        do {
            try await CSSearchableIndex.default().indexSearchableItems(items)
            return true
        } catch {
            debugPrint("Spotlight indexing failed: \(error)")
            return false
        }
    }

    private static func deleteItems(_ identifiers: [String]) async -> Bool {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
            return true
        } catch {
            debugPrint("Spotlight delete failed: \(error)")
            return false
        }
    }

    private static func deleteDomains(_ domains: [String]) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domains)
        } catch {
            debugPrint("Spotlight domain delete failed: \(error)")
        }
    }

    // MARK: - Helpers

    private static func displayName(for library: PicLibrary) -> String {
        if library.isDefault && library.name.isEmpty {
            return String(localized: "Collection.Default", table: "Libraries")
        }
        return library.name
    }

    private static func signature(_ fields: [String]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in ([schemaVersion] + fields).joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func databaseExists(forLibraryID libraryID: String) -> Bool {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) else { return false }
        let folderURL = libraryID == PicLibrary.defaultID
            ? appGroupURL : appGroupURL.appendingPathComponent(libraryID)
        return FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("Collection.db").path)
    }

    // MARK: - Index state

    private static var stateDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Spotlight", isDirectory: true)
    }

    private static func stateURL(forLibraryID libraryID: String) -> URL? {
        stateDirectory?.appendingPathComponent("\(libraryID).json")
    }

    private static func storedLibraryIDs() -> Set<String> {
        guard let directory = stateDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
    }

    private static func loadState(forLibraryID libraryID: String) -> [String: UInt64]? {
        guard let url = stateURL(forLibraryID: libraryID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: UInt64].self, from: data)
    }

    private static func saveState(_ state: [String: UInt64], forLibraryID libraryID: String) {
        guard let directory = stateDirectory, let url = stateURL(forLibraryID: libraryID),
              FileManager.default.fileExists(atPath: directory.path),
              let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func removeState(forLibraryID libraryID: String) {
        guard let url = stateURL(forLibraryID: libraryID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
