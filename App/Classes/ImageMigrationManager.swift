import Engine
import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ImageMigrationManager {

    var isMigrating: Bool = false
    var phase: ImageMigrationPhase = .preparing
    var completed: Int = 0
    var total: Int = 0
    var latestThumbnail: Data?

    func runPendingMigrations() async {
        guard !isMigrating else { return }
        guard DatabaseMigrator.needsLibraryV2Migration() else { return }
        var pendingIDs: [String] = []
        for id in await LibrariesActor.shared.allLibraryIDs() {
            if await DataActor.instance(for: id).isLibraryV2MigrationComplete() {
                await LibrariesActor.shared.setLibraryMigrated(true, forID: id)
            } else {
                pendingIDs.append(id)
            }
        }
        guard !pendingIDs.isEmpty else {
            DatabaseMigrator.markLibraryV2MigrationComplete()
            return
        }
        beginMigration()
        for id in pendingIDs {
            await migrate(libraryID: id, alreadyChecked: true)
        }
        DatabaseMigrator.markLibraryV2MigrationComplete()
        endMigration()
    }

    func runIfNeeded(for libraryID: String) async {
        guard !isMigrating else { return }
        let dataActor = DataActor.instance(for: libraryID)
        guard await !dataActor.isLibraryV2MigrationComplete() else {
            await LibrariesActor.shared.setLibraryMigrated(true, forID: libraryID)
            return
        }
        beginMigration()
        await migrate(libraryID: libraryID, dataActor: dataActor, alreadyChecked: true)
        endMigration()
    }

    private func migrate(libraryID: String,
                         dataActor: DataActor? = nil,
                         alreadyChecked: Bool = false) async {
        let dataActor = dataActor ?? DataActor.instance(for: libraryID)
        if !alreadyChecked, await dataActor.isLibraryV2MigrationComplete() {
            await LibrariesActor.shared.setLibraryMigrated(true, forID: libraryID)
            return
        }
        phase = .copying
        completed = 0
        total = 0
        latestThumbnail = nil
        await dataActor.migrateImageBlobsToFiles { progress in
            self.phase = progress.phase
            self.completed = progress.completed
            self.total = progress.total
            if let thumbnail = progress.latestThumbnail {
                self.latestThumbnail = thumbnail
            }
        }
        await dataActor.markLibraryV2MigrationComplete()
        await LibrariesActor.shared.setLibraryMigrated(true, forID: libraryID)
    }

    private func beginMigration() {
        phase = .preparing
        completed = 0
        total = 0
        latestThumbnail = nil
        isMigrating = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endMigration() {
        UIApplication.shared.isIdleTimerDisabled = false
        isMigrating = false
    }
}
