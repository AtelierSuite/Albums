import Engine
import Foundation

extension OriginalsManager {

    func pendingUploadPicIDs(picIDs: [String], in collectionID: String) async -> [String] {
        var pending: [String] = []
        for id in picIDs {
            guard let url = cloudURL(forPicID: id, in: collectionID) else {
                pending.append(id)
                continue
            }
            if !isUploaded(url) {
                pending.append(id)
            }
        }
        return pending
    }

    @discardableResult
    func moveCloudOriginal(picID: String, mediaType: MediaType,
                           from sourceID: String, to destinationID: String) async -> Bool {
        guard let sourceURL = cloudURL(forPicID: picID, in: sourceID),
              downloadingStatus(sourceURL) != nil,
              let destinationDirectory = originalsDirectory(for: destinationID, mediaType: mediaType) else {
            return false
        }
        let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: destinationDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            return false
        }
        return await coordinatedMove(from: sourceURL, to: destinationURL)
    }

    private func coordinatedMove(from source: URL, to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var success = false
                coordinator.coordinate(
                    writingItemAt: source, options: .forMoving,
                    writingItemAt: destination, options: .forReplacing,
                    error: &coordinationError
                ) { sourceURL, destinationURL in
                    coordinator.item(at: sourceURL, willMoveTo: destinationURL)
                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                        coordinator.item(at: sourceURL, didMoveTo: destinationURL)
                        success = true
                    } catch {
                        success = false
                    }
                }
                continuation.resume(returning: success && coordinationError == nil)
            }
        }
    }
}
