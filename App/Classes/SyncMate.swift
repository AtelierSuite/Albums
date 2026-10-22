@preconcurrency import CloudKit
import Engine
import Foundation

extension Notification.Name {
    static let syncDidApplyRemoteChanges = Notification.Name("SyncDidApplyRemoteChanges")
    static let syncDidApplyLibraryChanges = Notification.Name("SyncDidApplyLibraryChanges")
}

actor SyncMate {

    static let shared = SyncMate()
    static let containerID = "iCloud.com.tsubuzaki.IllustMateSQLite"

    private let container: CKContainer
    private var engine: CKSyncEngine?
    private let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
    private let stateKey = "CKSyncEngineState"

    private var forcePushLibraries: Set<String> = []

    init() {
        container = CKContainer(identifier: Self.containerID)
    }

    var isRunning: Bool { engine != nil }

    func start() {
        guard engine == nil, !Self.isDisabledForScreenshots else { return }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        engine = CKSyncEngine(configuration)
    }

    func stop() {
        engine = nil
    }

    func enqueueChanges(forLibrary collectionID: String) async {
        guard let engine else { return }
        let zoneID = Self.zoneID(for: collectionID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        let dataActor = DataActor.instance(for: collectionID)
        let dirtyAlbums = await dataActor.dirtyAlbumIDs()
        let unsyncedAlbums = await dataActor.unsyncedAlbumIDs()
        let dirtyPics = await dataActor.dirtyPicIDs()
        let unsyncedPics = await dataActor.unsyncedPicIDs()
        let tombstones = await dataActor.pendingTombstones()
        let albumIDs = Array(Set(dirtyAlbums + unsyncedAlbums))
        let picIDs = Array(Set(dirtyPics + unsyncedPics))

        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for id in albumIDs + picIDs {
            pending.append(.saveRecord(CKRecord.ID(recordName: id, zoneID: zoneID)))
        }
        for tombstone in tombstones {
            pending.append(.deleteRecord(CKRecord.ID(recordName: tombstone.id, zoneID: zoneID)))
        }
        await debugLog("scan \(albumIDs.count)A \(picIDs.count)P \(tombstones.count)del")
        guard !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    func enqueueLibraryChanges() async {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.librariesZoneID))])

        let dirtyLibraries = await LibrariesActor.shared.dirtyLibraryIDs()
        let unsyncedLibraries = await LibrariesActor.shared.unsyncedLibraryIDs()
        let libraryIDs = Array(Set(dirtyLibraries + unsyncedLibraries))
        let tombstones = await LibrariesActor.shared.pendingLibraryTombstones()
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for id in libraryIDs {
            pending.append(.saveRecord(CKRecord.ID(recordName: id, zoneID: Self.librariesZoneID)))
        }
        for id in tombstones {
            pending.append(.deleteRecord(CKRecord.ID(recordName: id, zoneID: Self.librariesZoneID)))
        }
        if !tombstones.isEmpty {
            engine.state.add(pendingDatabaseChanges: tombstones.map { .deleteZone(Self.zoneID(for: $0)) })
        }
        await debugLog("lib scan \(libraryIDs.count) \(tombstones.count)del")
        guard !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    func deleteLibraryZone(forLibrary collectionID: String) async {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.deleteZone(Self.zoneID(for: collectionID))])
    }

    func enqueueAllChanges(forLibrary collectionID: String) async {
        guard let engine else { return }
        let zoneID = Self.zoneID(for: collectionID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        let dataActor = DataActor.instance(for: collectionID)
        let albumIDs = await dataActor.allAlbumIDs()
        let picIDs = await dataActor.allOriginalPicIDs()

        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for id in albumIDs + picIDs {
            pending.append(.saveRecord(CKRecord.ID(recordName: id, zoneID: zoneID)))
        }
        await debugLog("force scan \(albumIDs.count)A \(picIDs.count)P")
        guard !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    func setForcePush(_ enabled: Bool, forLibrary collectionID: String) {
        if enabled {
            forcePushLibraries.insert(collectionID)
        } else {
            forcePushLibraries.remove(collectionID)
        }
    }

    func isForcePushing(_ collectionID: String) -> Bool {
        forcePushLibraries.contains(collectionID)
    }

    func hasPendingChanges() -> Bool {
        guard let engine else { return false }
        return !engine.state.pendingRecordZoneChanges.isEmpty
    }

    func fetchChanges() async {
        guard let engine else { return }
        try? await engine.fetchChanges()
    }

    func sendChanges() async {
        guard let engine else { return }
        try? await engine.sendChanges()
    }

    private static var isDisabledForScreenshots: Bool {
        #if DEBUG
        ScreenshotSeeder.isActive
        #else
        false
        #endif
    }

    func isAccountAvailable() async -> Bool {
        guard !Self.isDisabledForScreenshots else { return false }
        return (try? await container.accountStatus()) == .available
    }

    func remoteZoneNames() async -> Set<String>? {
        guard !Self.isDisabledForScreenshots else { return nil }
        guard let zones = try? await container.privateCloudDatabase.allRecordZones() else { return nil }
        return Set(zones.map { $0.zoneID.zoneName })
    }

    @discardableResult
    func fetchAndApplyRemoteLibraries() async -> Bool {
        guard let result = try? await container.privateCloudDatabase
            .recordZoneChanges(inZoneWith: Self.librariesZoneID, since: nil) else {
            return false
        }
        var changed = false
        for (_, modification) in result.modificationResultsByID {
            guard let record = try? modification.get().record else { continue }
            await LibrariesActor.shared.applyRemoteLibrary(Self.librarySnapshot(
                from: record,
                systemFields: Self.encodeSystemFields(record),
                lastModified: (record.modificationDate ?? Date.now).timeIntervalSince1970
            ))
            changed = true
        }
        return changed
    }

    // MARK: - Zone <-> library mapping

    static let librariesZoneName = "Libraries"

    static var librariesZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: librariesZoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func zoneName(for collectionID: String) -> String {
        collectionID == PicLibrary.defaultID ? "DefaultLibrary" : "Library-\(collectionID)"
    }

    static func zoneID(for collectionID: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: collectionID), ownerName: CKCurrentUserDefaultName)
    }

    static func collectionID(forZone zoneID: CKRecordZone.ID) -> String {
        let name = zoneID.zoneName
        if name == "DefaultLibrary" { return PicLibrary.defaultID }
        if name.hasPrefix("Library-") { return String(name.dropFirst("Library-".count)) }
        return PicLibrary.defaultID
    }

    static func libraryCollectionIDs(fromZoneNames zoneNames: Set<String>) -> [String] {
        zoneNames.compactMap { name in
            if name == "DefaultLibrary" { return PicLibrary.defaultID }
            return name.hasPrefix("Library-") ? String(name.dropFirst("Library-".count)) : nil
        }
    }

    // MARK: - State persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = defaults?.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func saveState(_ state: CKSyncEngine.State.Serialization) {
        defaults?.set(try? JSONEncoder().encode(state), forKey: stateKey)
    }

    func clearState() {
        defaults?.removeObject(forKey: stateKey)
    }

    // MARK: - Debug

    func debugLog(_ message: String) async {
        #if DEBUG
        await SyncDebugMonitor.shared.log(message)
        #endif
    }

    func reportAccountStatus() async {
        #if DEBUG
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        await SyncDebugMonitor.shared.setAccount(Self.describe(status))
        #endif
    }

    #if DEBUG
    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .noAccount: "no account"
        case .restricted: "restricted"
        case .couldNotDetermine: "unknown"
        case .temporarilyUnavailable: "unavailable"
        @unknown default: "unknown"
        }
    }
    #endif
}
