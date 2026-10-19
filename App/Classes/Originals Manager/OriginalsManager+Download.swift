import Engine
import Foundation

extension OriginalsManager {

    enum DownloadOutcome {
        case downloaded
        case timedOut
        case unavailable
    }

    struct DownloadState {
        let status: URLUbiquitousItemDownloadingStatus?
        let isDownloading: Bool
        let error: NSError?
    }

    static let downloadTickCap = 1200

    private func isMaterialized(_ url: URL) -> Bool {
        downloadingStatus(url) == .current
    }

    @discardableResult
    func materializeOriginal(picID: String, in collectionID: String) async -> Bool {
        guard let url = cloudURL(forPicID: picID, in: collectionID) else { return false }
        if isMaterialized(url) { return true }
        requestDownload(url)
        return await waitForDownload(url) == .downloaded
    }

    func picIDsNotMaterialized(in collectionID: String) async -> [String] {
        let ids = await DataActor.instance(for: collectionID).allOriginalPicIDs()
        return ids.filter { id in
            guard let url = cloudURL(forPicID: id, in: collectionID) else { return false }
            return !isMaterialized(url)
        }
    }

    func downloadAllOriginals(in collectionID: String) async {
        let ids = await DataActor.instance(for: collectionID).allOriginalPicIDs()
        for id in ids {
            guard let url = cloudURL(forPicID: id, in: collectionID), !isMaterialized(url) else { continue }
            requestDownload(url)
        }
    }

    func startAlbumOfflineDownloads(albumID: String, in collectionID: String) async {
        let ids = await DataActor.instance(for: collectionID).allOriginalPicIDs(inAlbum: albumID)
        for id in ids {
            guard let url = cloudURL(forPicID: id, in: collectionID), !isMaterialized(url) else { continue }
            requestDownload(url)
        }
    }

    func keepAlbumOffline(albumID: String, in collectionID: String) async {
        let allIDs = await DataActor.instance(for: collectionID).allOriginalPicIDs(inAlbum: albumID)
        let pending = allIDs.filter { id in
            guard let url = cloudURL(forPicID: id, in: collectionID) else { return false }
            return !isMaterialized(url)
        }
        guard !pending.isEmpty else { return }
        await postAlbumProgress(albumID, fraction: 0)
        var done = 0
        for id in pending {
            await materializeOriginal(picID: id, in: collectionID)
            done += 1
            await postAlbumProgress(albumID, fraction: Double(done) / Double(pending.count))
        }
        await postAlbumProgress(albumID, fraction: nil)
    }

    private func postAlbumProgress(_ albumID: String, fraction: Double?) async {
        await MainActor.run {
            var info: [String: Any] = ["albumID": albumID]
            if let fraction { info["fraction"] = fraction }
            NotificationCenter.default.post(name: Notification.Name("OfflineAlbumDownloadProgress"),
                                            object: nil, userInfo: info)
        }
    }

    func removeAlbumDownload(albumID: String, in collectionID: String) async {
        let dataActor = DataActor.instance(for: collectionID)
        for id in await dataActor.localOriginalPicIDs(inAlbum: albumID) {
            guard let cloudURL = cloudURL(forPicID: id, in: collectionID), isUploaded(cloudURL) else {
                continue
            }
            await dataActor.evictLocalOriginal(picID: id)
            try? FileManager.default.evictUbiquitousItem(at: cloudURL)
        }
    }

    func prefetchOriginals(picIDs: [String], in collectionID: String) async {
        for picID in picIDs {
            guard let url = cloudURL(forPicID: picID, in: collectionID),
                  !isMaterialized(url) else { continue }
            requestDownload(url)
        }
        await SyncMate.shared.debugLog("prefetch: requested \(picIDs.count)")
    }

    func fetchOriginal(picID: String, in collectionID: String,
                       timeoutSeconds: Int = 10, retries: Int = 0,
                       retryDelaySeconds: Int = 3) async -> Data? {
        guard let cloudURL = cloudURL(forPicID: picID, in: collectionID) else {
            await SyncMate.shared.debugLog("fetch: no container")
            return nil
        }
        for attempt in 0...max(retries, 0) {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(retryDelaySeconds))
                await SyncMate.shared.debugLog("fetch \(picID.prefix(6)): retry \(attempt)")
            }
            requestDownload(cloudURL)
            let outcome = await waitForDownload(cloudURL, timeoutSeconds: timeoutSeconds)
            guard outcome != .unavailable else {
                await SyncMate.shared.debugLog("fetch \(picID.prefix(6)): unavailable")
                return nil
            }
            guard outcome == .downloaded else {
                await SyncMate.shared.debugLog("fetch \(picID.prefix(6)): timeout \(statusLabel(cloudURL))")
                continue
            }
            guard let data = await coordinatedReadData(at: cloudURL) else {
                await SyncMate.shared.debugLog("fetch \(picID.prefix(6)): read fail")
                continue
            }
            await SyncMate.shared.debugLog("fetch \(picID.prefix(6)): ok \(data.count / 1024)KB")
            return data
        }
        return nil
    }

    func materializedVideoURL(picID: String, in collectionID: String) async -> URL? {
        guard let url = cloudURL(forPicID: picID, in: collectionID) else {
            await SyncMate.shared.debugLog("video \(picID.prefix(6)): no container")
            return nil
        }
        if isMaterialized(url) { return url }
        requestDownload(url)
        if await waitForDownload(url) == .downloaded {
            await SyncMate.shared.debugLog("video \(picID.prefix(6)): ok")
            return url
        }
        await SyncMate.shared.debugLog("video \(picID.prefix(6)): timeout \(statusLabel(url))")
        return nil
    }

    private func waitForDownload(_ url: URL, timeoutSeconds: Int = 10) async -> DownloadOutcome {
        if downloadingStatus(url) == .current { return .downloaded }
        // A nil downloading status means iCloud holds no such item at all, so waiting
        // can never produce one.
        guard downloadingStatus(url) != nil else { return .unavailable }
        requestDownload(url)
        let idleLimit = timeoutSeconds * 2
        var idleTicks = 0
        var elapsedTicks = 0
        while idleTicks < idleLimit && elapsedTicks < Self.downloadTickCap {
            try? await Task.sleep(for: .milliseconds(500))
            elapsedTicks += 1
            let state = downloadState(url)
            if state.status == .current { return .downloaded }
            guard state.status != nil else { return .unavailable }
            if state.error != nil { return .timedOut }
            if state.isDownloading {
                idleTicks = 0
            } else {
                idleTicks += 1
                if idleTicks.isMultiple(of: 10) {
                    requestDownload(url)
                }
            }
        }
        return downloadingStatus(url) == .current ? .downloaded : .timedOut
    }

    private func downloadState(_ url: URL) -> DownloadState {
        let values = cloudResourceValues(at: url, keys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingErrorKey
        ])
        return DownloadState(status: values?.ubiquitousItemDownloadingStatus,
                             isDownloading: values?.ubiquitousItemIsDownloading ?? false,
                             error: values?.ubiquitousItemDownloadingError)
    }

    private func statusLabel(_ url: URL) -> String {
        downloadingStatus(url)?.rawValue
            .replacingOccurrences(of: "NSURLUbiquitousItemDownloadingStatus", with: "") ?? "unknown"
    }
}
