import Engine
import Foundation

@MainActor
final class SyncManager {

    static let shared = SyncManager()

    func canEnableSync() async -> Bool {
        guard await SyncMate.shared.isAccountAvailable() else { return false }
        return await OriginalsManager.shared.isUbiquityAvailable()
    }

    private var pendingPushLibraries: Set<String> = []
    private var pushDebounceTask: Task<Void, Never>?

    func schedulePush(forLibrary collectionID: String) {
        pendingPushLibraries.insert(collectionID)
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { [self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let libraries = pendingPushLibraries
            pendingPushLibraries.removeAll()
            for id in libraries {
                await pushChanges(forLibrary: id)
            }
        }
    }

    func pushChanges(forLibrary collectionID: String) async {
        let enabledIDs = await LibrariesActor.shared.syncEnabledLibraryIDs()
        guard enabledIDs.contains(collectionID) else { return }
        await SyncMate.shared.start()
        await SyncMate.shared.enqueueChanges(forLibrary: collectionID)
        await SyncMate.shared.sendChanges()
    }

    func deleteLibraryFromCloud(_ collectionID: String) async {
        guard await SyncMate.shared.isAccountAvailable() else { return }
        await SyncMate.shared.start()
        await SyncMate.shared.enqueueLibraryChanges()
        await SyncMate.shared.deleteLibraryZone(forLibrary: collectionID)
        await SyncMate.shared.sendChanges()
    }

    func forcePush(forLibrary collectionID: String) async {
        guard await SyncMate.shared.isAccountAvailable() else { return }
        let enabledIDs = await LibrariesActor.shared.syncEnabledLibraryIDs()
        guard enabledIDs.contains(collectionID) else { return }

        await SyncMate.shared.start()
        await SyncMate.shared.setForcePush(true, forLibrary: collectionID)
        await SyncMate.shared.enqueueAllChanges(forLibrary: collectionID)

        var attempts = 0
        repeat {
            await SyncMate.shared.sendChanges()
            attempts += 1
        } while await SyncMate.shared.hasPendingChanges() && attempts < 8

        await SyncMate.shared.setForcePush(false, forLibrary: collectionID)
        await OriginalsManager.shared.resetSyncStateIfContainerChanged()
        await OriginalsManager.shared.uploadMissingOriginals(in: collectionID)
    }

    func refresh() async {
        for id in await LibrariesActor.shared.unmigratedLibraryIDs() {
            if await DataActor.instance(for: id).isLibraryV2MigrationComplete() {
                await LibrariesActor.shared.setLibraryMigrated(true, forID: id)
            }
        }

        guard await SyncMate.shared.isAccountAvailable() else {
            await SyncMate.shared.stop()
            return
        }

        let enabledIDs = await LibrariesActor.shared.syncEnabledLibraryIDs()
        #if DEBUG
        SyncDebugMonitor.shared.enabled = true
        #endif

        await SyncMate.shared.start()
        await SyncMate.shared.reportAccountStatus()
        await SyncMate.shared.enqueueLibraryChanges()
        for id in enabledIDs {
            await SyncMate.shared.enqueueChanges(forLibrary: id)
        }
        await SyncMate.shared.fetchChanges()

        let downloadEnabledIDs = await LibrariesActor.shared.syncEnabledLibraryIDs()
        guard !downloadEnabledIDs.isEmpty else { return }

        await OriginalsManager.shared.resetSyncStateIfContainerChanged()
        for id in downloadEnabledIDs {
            Task.detached(priority: .utility) {
                await OriginalsManager.shared.uploadMissingOriginals(in: id)
                await OriginalsManager.shared.reclaimUploadedOriginals(in: id)
            }
        }
        for id in await LibrariesActor.shared.downloadAllLibraryIDs() {
            Task.detached(priority: .utility) {
                await OriginalsManager.shared.downloadAllOriginals(in: id)
            }
        }
        let enabled = Set(downloadEnabledIDs)
        for (albumID, collectionID) in OfflineAlbums.all() where enabled.contains(collectionID) {
            Task.detached(priority: .utility) {
                await OriginalsManager.shared.keepAlbumOffline(albumID: albumID, in: collectionID)
            }
        }
    }

    func backgroundSync() async {
        for id in await LibrariesActor.shared.unmigratedLibraryIDs() {
            if await DataActor.instance(for: id).isLibraryV2MigrationComplete() {
                await LibrariesActor.shared.setLibraryMigrated(true, forID: id)
            }
        }

        guard await SyncMate.shared.isAccountAvailable() else {
            await SyncMate.shared.stop()
            return
        }

        let enabledIDs = await LibrariesActor.shared.syncEnabledLibraryIDs()
        await SyncMate.shared.start()
        await SyncMate.shared.enqueueLibraryChanges()
        for id in enabledIDs {
            await SyncMate.shared.enqueueChanges(forLibrary: id)
        }
        await SyncMate.shared.fetchChanges()
        await SyncMate.shared.sendChanges()

        guard !enabledIDs.isEmpty else { return }

        await OriginalsManager.shared.resetSyncStateIfContainerChanged()
        for id in enabledIDs {
            await OriginalsManager.shared.uploadMissingOriginals(in: id)
            await OriginalsManager.shared.reclaimUploadedOriginals(in: id, waitForUploads: false)
        }
        for id in await LibrariesActor.shared.downloadAllLibraryIDs() {
            await OriginalsManager.shared.downloadAllOriginals(in: id)
        }
        let enabled = Set(enabledIDs)
        for (albumID, collectionID) in OfflineAlbums.all() where enabled.contains(collectionID) {
            await OriginalsManager.shared.startAlbumOfflineDownloads(albumID: albumID, in: collectionID)
        }
    }
}
