import Engine
import Foundation
import SwiftUI

@MainActor
class LibraryManager: ObservableObject {

    @Published var currentLibrary: PicLibrary = PicLibrary()
    @Published var libraries: [PicLibrary] = []
    @Published var hasLoadedLibraries: Bool = false

    @AppStorage("CurrentCollectionID",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var currentLibraryID: String = PicLibrary.defaultID
    @AppStorage("PhotosModeEnabled",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false

    private func sortedByName(_ libraries: [PicLibrary]) -> [PicLibrary] {
        libraries.sorted { lhs, rhs in
            if lhs.isDefault { return true }
            if rhs.isDefault { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func loadLibraries() async {
        let allLibraries = await LibrariesActor.shared.allLibraries()
        withAnimation(.smooth.speed(2.0)) {
            libraries = sortedByName(allLibraries)
        }

        if let saved = allLibraries.first(where: { $0.id == currentLibraryID }) {
            currentLibrary = saved
        } else {
            currentLibrary = allLibraries.first(where: { $0.isDefault }) ?? PicLibrary()
            currentLibraryID = PicLibrary.defaultID
        }
        switchActors(to: currentLibrary.id)
        hasLoadedLibraries = true
    }

    func reloadList() async {
        let allLibraries = await LibrariesActor.shared.allLibraries()
        withAnimation(.smooth.speed(2.0)) {
            libraries = sortedByName(allLibraries)
        }
        if !currentLibrary.isDefault,
           !allLibraries.contains(where: { $0.id == currentLibrary.id }) {
            switchLibrary(to: PicLibrary())
        }
    }

    func reconcileWithICloud() async {
        guard let remoteZoneNames = await SyncMate.shared.remoteZoneNames() else { return }

        if remoteZoneNames.contains(SyncMate.zoneName(for: PicLibrary.defaultID)) {
            await LibrariesActor.shared.setSyncEnabled(true, forID: PicLibrary.defaultID)
        }

        if remoteZoneNames.contains(SyncMate.librariesZoneName) {
            await SyncMate.shared.fetchAndApplyRemoteLibraries()
        }

        let localIDs = Set(await LibrariesActor.shared.allLibraryIDs())
        for id in SyncMate.libraryCollectionIDs(fromZoneNames: remoteZoneNames)
        where !localIDs.contains(id) {
            await LibrariesActor.shared.insertRemoteLibraryStub(id: id)
        }

        for id in await LibrariesActor.shared.confirmedSyncedLibraryIDs()
        where !remoteZoneNames.contains(SyncMate.zoneName(for: id)) {
            await LibrariesActor.shared.removeLibraryForRemoteDelete(id: id)
            if currentLibrary.id == id {
                switchLibrary(to: PicLibrary())
            }
        }

        await loadLibraries()
    }

    func switchLibrary(to library: PicLibrary) {
        isPhotosModeEnabled = false
        currentLibrary = library
        currentLibraryID = library.id
        switchActors(to: library.id)
        AlbumCoverCache.shared.removeAllImages()
    }

    func createLibrary(name: String, syncEnabled: Bool = false) async -> PicLibrary {
        let library = await LibrariesActor.shared.createLibrary(name: name)
        if syncEnabled {
            if await DataActor.instance(for: library.id).isLibraryV2MigrationComplete() {
                await LibrariesActor.shared.setLibraryMigrated(true, forID: library.id)
            }
            await LibrariesActor.shared.setSyncEnabled(true, forID: library.id)
            library.syncEnabled = true
        }
        await loadLibraries()
        if syncEnabled {
            await SyncManager.shared.refresh()
        }
        return library
    }

    func renameLibrary(_ library: PicLibrary, to newName: String) async {
        await LibrariesActor.shared.renameLibrary(withID: library.id, to: newName)
        await loadLibraries()
        if currentLibrary.id == library.id {
            currentLibrary.name = newName.trimmingCharacters(in: .whitespaces)
        }
    }

    func deleteLibrary(_ library: PicLibrary) async {
        guard !library.isDefault else { return }
        await OriginalsManager.shared.deleteAllOriginals(in: library.id)
        await LibrariesActor.shared.deleteLibrary(withID: library.id)
        await SyncManager.shared.deleteLibraryFromCloud(library.id)
        if currentLibrary.id == library.id {
            let defaultLibrary = PicLibrary()
            switchLibrary(to: defaultLibrary)
        }
        await loadLibraries()
    }

    private func switchActors(to libraryID: String) {
        DataActor.switchLibrary(to: libraryID)
        HashActor.switchLibrary(to: libraryID)
        CoverCacheActor.switchLibrary(to: libraryID)
        PColorActor.switchLibrary(to: libraryID)
        FeaturePrintActor.switchLibrary(to: libraryID)
        AlbumModelActor.switchLibrary(to: libraryID)
    }

    func displayName(for library: PicLibrary) -> String {
        if library.isDefault {
            return String(localized: "Collection.Default", table: "Libraries")
        }
        return library.name
    }
}
