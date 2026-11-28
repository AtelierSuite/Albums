import Engine
import SwiftUI

struct MacRootView: View {

    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ImageMigrationManager.self) var imageMigration

    var body: some View {
        MainSplitView()
            .modifier(SpotlightModifier())
            .modifier(ContentCredentialsModifier())
            .modifier(ImportRecoveryModifier())
            .overlay(alignment: .top) {
                ToastOverlayView(priority: -1, topPadding: 56.0) {
                    navigation.signalDataChanged()
                }
            }
            .task {
                await libraryManager.loadLibraries()
                await imageMigration.runPendingMigrations()
                DatabaseMigrator.markMigrationComplete()
                await libraryManager.reconcileWithICloud()
                await RecentlyDeleted.purgeExpired(in: libraryManager.currentLibrary.id)
                await SyncManager.shared.refresh()
            }
            .onChange(of: libraryManager.currentLibrary.id) { _, newID in
                Task {
                    await imageMigration.runIfNeeded(for: newID)
                    await RecentlyDeleted.purgeExpired(in: newID)
                    await SyncManager.shared.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyRemoteChanges)) { note in
                for albumID in note.object as? [String] ?? [] {
                    AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
                }
                navigation.signalDataChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataActorDidMutateLocally)) { note in
                if let collectionID = note.object as? String {
                    Task { @MainActor in
                        SyncManager.shared.schedulePush(forLibrary: collectionID)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyLibraryChanges)) { note in
                let removedLibraryIDs = note.object as? [String] ?? []
                Task { await libraryManager.reloadList(removedLibraryIDs: removedLibraryIDs) }
            }
    }
}
