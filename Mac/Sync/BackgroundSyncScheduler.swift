import Foundation

@MainActor
final class BackgroundSyncScheduler {

    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.tsubuzaki.IllustMate.iCloudSync")

    func start() {
        scheduler.repeats = true
        scheduler.interval = 60.0 * 60.0
        scheduler.tolerance = 60.0 * 10.0
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await SyncManager.shared.backgroundSync()
                completion(.finished)
            }
        }
    }
}
