import Engine
import Foundation

extension OriginalsManager {

    func libraryOriginalsDirectory(for collectionID: String) -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)?
            .appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(collectionID, isDirectory: true)
    }

    func originalsDirectory(for collectionID: String, mediaType: MediaType) -> URL? {
        let subfolder = mediaType == .video ? "Videos" : "Images"
        return libraryOriginalsDirectory(for: collectionID)?
            .appendingPathComponent(subfolder, isDirectory: true)
    }

    func cloudURL(forPicID id: String, in collectionID: String) -> URL? {
        if let imagesDirectory = originalsDirectory(for: collectionID, mediaType: .pic) {
            let imageURL = imagesDirectory.appendingPathComponent(id)
            if downloadingStatus(imageURL) != nil { return imageURL }
        }
        if let videosDirectory = originalsDirectory(for: collectionID, mediaType: .video),
           let videoURL = enumerateVideoOriginal(in: videosDirectory, picID: id) {
            return videoURL
        }
        if let legacyURL = legacyOriginalURL(forPicID: id, in: collectionID),
           downloadingStatus(legacyURL) != nil {
            return legacyURL
        }
        return originalsDirectory(for: collectionID, mediaType: .pic)?.appendingPathComponent(id)
    }

    private func legacyOriginalURL(forPicID id: String, in collectionID: String) -> URL? {
        libraryOriginalsDirectory(for: collectionID)?.appendingPathComponent(id)
    }

    private func enumerateVideoOriginal(in directory: URL, picID: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return nil }
        for url in items {
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            if (name as NSString).deletingPathExtension == picID {
                return directory.appendingPathComponent(name)
            }
        }
        return nil
    }

    /// The on-disk name of a pic's original in the ubiquity container (e.g. `<id>.mov` for videos,
    /// the bare id for images). Used to drive the download-progress query, which matches by filename.
    func cloudOriginalFilename(picID: String, in collectionID: String) -> String? {
        cloudURL(forPicID: picID, in: collectionID)?.lastPathComponent
    }

    func hasCloudOriginal(picID: String, in collectionID: String) -> Bool {
        guard let url = cloudURL(forPicID: picID, in: collectionID) else { return false }
        return downloadingStatus(url) != nil
    }

    func originalSize(picID: String, in collectionID: String) async -> Int64? {
        guard let url = cloudURL(forPicID: picID, in: collectionID) else { return nil }
        let values = cloudResourceValues(at: url, keys: [.fileSizeKey, .totalFileSizeKey])
        if let total = values?.totalFileSize { return Int64(total) }
        if let size = values?.fileSize { return Int64(size) }
        return nil
    }

    nonisolated func cloudImageOriginalURL(forPicID id: String, in collectionID: String) -> URL? {
        cloudOriginalsSubdirectory(named: "Images", in: collectionID)?
            .appendingPathComponent(id)
    }

    nonisolated func cloudVideoOriginalExtension(forPicID id: String, in collectionID: String) -> String? {
        guard let directory = cloudOriginalsSubdirectory(named: "Videos", in: collectionID),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        for entry in entries {
            var name = entry
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            if (name as NSString).deletingPathExtension == id {
                let ext = (name as NSString).pathExtension
                return ext.isEmpty ? nil : ext
            }
        }
        return nil
    }

    private nonisolated func cloudOriginalsSubdirectory(named name: String, in collectionID: String) -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)?
            .appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(collectionID, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
