import Engine
import Foundation

extension Notification.Name {
    static let picContentCredentialsDidChange = Notification.Name("PicContentCredentialsDidChange")
}

actor ContentCredentialsScanner {

    static let shared = ContentCredentialsScanner()

    private static let batchSize = 25

    private var pendingLibraryIDs: Set<String> = []
    private var needsFullScan = false
    private var isScanning = false
    private var debounceTask: Task<Void, Never>?

    func scheduleScan(libraryIDs: [String]? = nil, after delay: Duration = .seconds(1)) {
        if let libraryIDs {
            pendingLibraryIDs.formUnion(libraryIDs)
        } else {
            needsFullScan = true
        }
        debounceTask?.cancel()
        debounceTask = Task(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            Task(priority: .utility) { await self.drain() }
        }
    }

    func ensureScanned(picID: String, imageData: Data, in dataActor: DataActor) async {
        guard await dataActor.contentCredentialsVersion(forPicWithID: picID)
                < ContentCredentialsReader.version else { return }
        await store(ContentCredentialsReader.read(.imageData(imageData)), forPicID: picID, in: dataActor)
    }

    private func drain() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        while needsFullScan || !pendingLibraryIDs.isEmpty {
            let requestedIDs: Set<String>? = needsFullScan ? nil : pendingLibraryIDs
            needsFullScan = false
            pendingLibraryIDs.removeAll()
            for library in await LibrariesActor.shared.allLibraries()
            where requestedIDs?.contains(library.id) ?? true {
                guard SpotlightIndexer.databaseExists(forLibraryID: library.id) else { continue }
                await scanLibrary(DataActor.instance(for: library.id))
            }
        }
    }

    private func scanLibrary(_ dataActor: DataActor) async {
        var skippedIDs: Set<String> = []
        while true {
            let picIDs = await dataActor.picIDsNeedingContentCredentialsScan(
                version: ContentCredentialsReader.version, limit: Self.batchSize + skippedIDs.count
            ).filter { !skippedIDs.contains($0) }
            guard !picIDs.isEmpty else { return }
            for picID in picIDs {
                if Task.isCancelled { return }
                if await !scan(picID: picID, in: dataActor) {
                    skippedIDs.insert(picID)
                }
            }
        }
    }

    @discardableResult
    func scan(picID: String, in dataActor: DataActor) async -> Bool {
        guard let source = await dataActor.contentCredentialsSource(forPicWithID: picID) else { return false }
        await store(ContentCredentialsReader.read(source), forPicID: picID, in: dataActor)
        return true
    }

    private func store(_ credentials: ContentCredentials?, forPicID picID: String,
                       in dataActor: DataActor) async {
        await dataActor.setContentCredentials(credentials, version: ContentCredentialsReader.version,
                                              forPicWithID: picID)
        guard credentials != nil else { return }
        let kind = credentials?.aiContentKind?.rawValue
        await MainActor.run {
            NotificationCenter.default.post(name: .picContentCredentialsDidChange, object: picID,
                                            userInfo: ["aiContent": kind as Any])
        }
    }
}
