import Foundation

extension OriginalsManager {

    func coordinatedCopy(from source: URL, to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var success = false
                coordinator.coordinate(
                    writingItemAt: destination, options: .forReplacing, error: &coordinationError
                ) { writeURL in
                    do {
                        if FileManager.default.fileExists(atPath: writeURL.path) {
                            try FileManager.default.removeItem(at: writeURL)
                        }
                        try FileManager.default.copyItem(at: source, to: writeURL)
                        success = true
                    } catch {
                        success = false
                    }
                }
                continuation.resume(returning: success && coordinationError == nil)
            }
        }
    }

    func coordinatedWrite(_ data: Data, to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var success = false
                coordinator.coordinate(
                    writingItemAt: destination, options: .forReplacing, error: &coordinationError
                ) { writeURL in
                    success = (try? data.write(to: writeURL, options: .atomic)) != nil
                }
                continuation.resume(returning: success && coordinationError == nil)
            }
        }
    }

    func coordinatedReadData(at url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var data: Data?
                coordinator.coordinate(
                    readingItemAt: url, options: [], error: &coordinationError
                ) { readURL in
                    data = try? Data(contentsOf: readURL)
                }
                continuation.resume(returning: data)
            }
        }
    }

    func coordinatedDelete(at url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                coordinator.coordinate(
                    writingItemAt: url, options: .forDeleting, error: &coordinationError
                ) { deleteURL in
                    try? FileManager.default.removeItem(at: deleteURL)
                }
                continuation.resume()
            }
        }
    }
}
