import Engine
import Foundation

extension OriginalsManager {

    @discardableResult
    func uploadOriginal(picID: String, in collectionID: String) async -> OriginalUploadOutcome {
        let dataActor = DataActor.instance(for: collectionID)
        guard let location = await dataActor.originalLocation(forPicWithID: picID) else {
            return .noLocalFile
        }
        guard let directory = originalsDirectory(for: collectionID, mediaType: location.mediaType) else {
            return .noContainer
        }
        guard let filename = location.filename else { return .noLocalFile }
        let cloudURL = directory.appendingPathComponent(filename)
        if downloadingStatus(cloudURL) != nil {
            await dataActor.markPicOriginalSynced(id: picID)
            return .alreadyPresent
        }
        guard let localURL = location.localURL else { return .noLocalFile }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard await coordinatedCopy(from: localURL, to: cloudURL) else {
            return .failed("coordinated write failed")
        }
        await dataActor.markPicOriginalSynced(id: picID)
        return .uploaded
    }

    func uploadMissingOriginals(in collectionID: String) async {
        guard !uploadingMissing.contains(collectionID) else { return }
        uploadingMissing.insert(collectionID)
        defer { uploadingMissing.remove(collectionID) }
        let dataActor = DataActor.instance(for: collectionID)
        let ids = await dataActor.picIDsNeedingOriginalUpload()
        await SyncMate.shared.debugLog("orig \(collectionID.prefix(4)): \(ids.count) to mirror")
        guard !ids.isEmpty else { return }
        var up = 0, present = 0, noLocal = 0, failed = 0, noCont = 0
        var sampleError: String?
        for id in ids {
            switch await uploadOriginal(picID: id, in: collectionID) {
            case .uploaded: up += 1
            case .alreadyPresent: present += 1
            case .noContainer: noCont += 1
            case .noLocalFile: noLocal += 1
            case .failed(let message):
                failed += 1
                if sampleError == nil { sampleError = message }
            }
        }
        await SyncMate.shared.debugLog("orig done: \(up)up \(present)pre \(noLocal)noloc \(failed)err \(noCont)noc")
        if let sampleError { await SyncMate.shared.debugLog("orig err: \(sampleError)") }
    }

    func reclaimUploadedOriginals(in collectionID: String, waitForUploads: Bool = true) async {
        guard !reclaiming.contains(collectionID) else { return }
        reclaiming.insert(collectionID)
        defer { reclaiming.remove(collectionID) }
        let dataActor = DataActor.instance(for: collectionID)
        var reclaimed = 0
        var consecutiveTimeouts = 0
        for id in await dataActor.localOriginalPicIDs() {
            guard let location = await dataActor.originalLocation(forPicWithID: id),
                  location.localURL != nil,
                  let cloudURL = cloudURL(forPicID: id, in: collectionID),
                  downloadingStatus(cloudURL) != nil else { continue }
            var uploaded = isUploaded(cloudURL)
            // Foreground only: wait for the just-mirrored original to finish uploading
            // before deleting the device-local copy, but stop once uploads clearly
            // aren't progressing (offline / paused) so this can't hang a large library.
            // Background sync never waits — it only reclaims already-uploaded copies.
            if !uploaded, waitForUploads, consecutiveTimeouts < 3 {
                uploaded = await waitForUpload(cloudURL)
                consecutiveTimeouts = uploaded ? 0 : consecutiveTimeouts + 1
            }
            guard uploaded else { continue }
            await dataActor.evictLocalOriginal(picID: id)
            reclaimed += 1
        }
        if reclaimed > 0 {
            await SyncMate.shared.debugLog("orig \(collectionID.prefix(4)): reclaimed \(reclaimed) local")
        }
    }

    func resetSyncStateIfContainerChanged() async {
        guard defaults?.string(forKey: containerMarkerKey) != Self.containerID else { return }
        for id in await LibrariesActor.shared.allLibraryIDs() {
            await DataActor.instance(for: id).resetOriginalSyncState()
        }
        defaults?.set(Self.containerID, forKey: containerMarkerKey)
        await SyncMate.shared.debugLog("orig: container changed, reset upload flags")
    }

    func isUploaded(_ url: URL) -> Bool {
        cloudResourceValues(at: url, keys: [.ubiquitousItemIsUploadedKey])?
            .ubiquitousItemIsUploaded ?? false
    }

    private func waitForUpload(_ url: URL, timeoutSeconds: Int = 8) async -> Bool {
        for _ in 0..<(timeoutSeconds * 2) {
            if isUploaded(url) { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return isUploaded(url)
    }
}
