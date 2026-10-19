import Foundation

extension DataActor {

    public static let videosDirectoryName = "Videos"

    public nonisolated func videosDirectoryURL() -> URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.videosDirectoryName, isDirectory: true)
    }

    public func ensureVideosDirectoryExists() {
        let url = videosDirectoryURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func saveVideoFile(_ data: Data, id: String, fileExtension: String) -> String? {
        ensureVideosDirectoryExists()
        let filename = "\(id).\(fileExtension)"
        let relativePath = "\(Self.videosDirectoryName)/\(filename)"
        let fileURL = videosDirectoryURL().appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return relativePath
        } catch {
            debugPrint("Failed to save video file: \(error)")
            return nil
        }
    }

    public nonisolated func videoFileURL(forRelativePath path: String) -> URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    public func deleteVideoFile(atRelativePath path: String) {
        let fileURL = videoFileURL(forRelativePath: path)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
