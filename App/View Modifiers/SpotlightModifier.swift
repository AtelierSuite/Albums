import CoreSpotlight
import Engine
import SwiftUI

struct SpotlightModifier: ViewModifier {

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ViewerManager.self) var viewer

    @AppStorage("AppLockEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isAppLockEnabled: Bool = false
    @AppStorage(spotlightIndexingEnabledKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isSpotlightIndexingEnabled: Bool = true

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    Task { await SpotlightIndexer.shared.scheduleReconcile() }
                }
            }
            .onChange(of: isAppLockEnabled) { _, _ in
                Task { await SpotlightIndexer.shared.scheduleReconcile(after: .zero) }
            }
            .onChange(of: isSpotlightIndexingEnabled) { _, _ in
                Task { await SpotlightIndexer.shared.scheduleReconcile(after: .zero) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataActorDidMutateLocally)) { note in
                if let collectionID = note.object as? String {
                    Task { await SpotlightIndexer.shared.scheduleReconcile(libraryIDs: [collectionID]) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyRemoteChanges)) { _ in
                Task { await SpotlightIndexer.shared.scheduleReconcile() }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let item = SpotlightItemID(identifier) else { return }
                Task { await open(item) }
            }
    }

    private func open(_ item: SpotlightItemID) async {
        for _ in 0..<50 where !libraryManager.hasLoadedLibraries {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let library = await LibrariesActor.shared.library(for: item.libraryID) else { return }
        if libraryManager.isPhotosModeEnabled || libraryManager.currentLibrary.id != library.id {
            libraryManager.switchLibrary(to: library)
            navigation.signalDataDeleted()
        }
        guard let (albumPath, pic) = await resolve(item) else { return }

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        navigation.popAll()
        if isPhone {
            navigation.collectionTabPath = [.library(id: library.id)]
        }
        try? await Task.sleep(for: .milliseconds(250))
        for album in albumPath {
            navigation.push(.album(album: album), for: .collection)
        }
        guard let pic else { return }
        let siblings = (try? await DataActor.shared.pics(in: albumPath.last, order: .reverse)) ?? [pic]
        viewer.setDisplay(pic, in: siblings) { [navigation] in
            if isPhone {
                navigation.push(.picViewerRestore, for: .collection)
            }
        }
    }

    private func resolve(_ item: SpotlightItemID) async -> ([Album], Pic?)? {
        let dataActor = DataActor.shared
        switch item.kind {
        case .album:
            let albumPath = await dataActor.albumPath(forAlbumWithID: item.itemID)
            return albumPath.isEmpty ? nil : (albumPath, nil)
        case .pic:
            guard let pic = try? await dataActor.pics(withIDs: [item.itemID]).first else { return nil }
            guard let albumID = pic.containingAlbumID else { return ([], pic) }
            return (await dataActor.albumPath(forAlbumWithID: albumID), pic)
        }
    }
}
