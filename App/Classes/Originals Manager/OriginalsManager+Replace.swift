import Engine
import Foundation

extension OriginalsManager {

    enum CloudOriginalReplaceOutcome: Sendable {
        case replaced
        case notMirrored
        case failed
    }

    func replaceCloudImageOriginal(picID: String, with data: Data,
                                   in collectionID: String) async -> CloudOriginalReplaceOutcome {
        let isSyncEnabled = await LibrariesActor.shared.syncEnabledLibraryIDs().contains(collectionID)
        guard isUbiquityAvailable() else { return isSyncEnabled ? .failed : .notMirrored }
        guard isSyncEnabled || hasCloudOriginal(picID: picID, in: collectionID) else { return .notMirrored }
        guard let directory = originalsDirectory(for: collectionID, mediaType: .pic) else { return .failed }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failed
        }
        let cloudURL = directory.appendingPathComponent(picID)
        guard await coordinatedWrite(data, to: cloudURL) else { return .failed }
        await SyncMate.shared.debugLog("orig \(picID.prefix(6)): replaced edited original")
        return .replaced
    }
}
