import Foundation
import ImageIO
@preconcurrency import SQLite
import UniformTypeIdentifiers

extension DataActor {

    private struct FolderBackupOptions {
        public let originalProvider: (@Sendable (String) async -> Data?)?
        public let prefetch: (@Sendable ([String]) async -> Void)?
        public let skipping: Set<String>
        public let progress: (@MainActor (Int, Int) -> Void)?
    }

    private struct FolderBackupSource {
        public let url: URL?
        public let data: Data?
    }

    private struct FolderBackupPic {
        public let id: String
        public let name: String
        public let albumID: String?
        public let mediaType: Int
        public let filePath: String?
        public let dateAdded: Date
    }

    public func exportFolderArchive(to destinationDirectoryURL: URL, libraryName: String,
                                    originalProvider: (@Sendable (String) async -> Data?)? = nil,
                                    sizeProvider: (@Sendable (String) async -> Int64?)? = nil,
                                    prefetch: (@Sendable ([String]) async -> Void)? = nil,
                                    skipping: Set<String> = [],
                                    progress: (@MainActor (Int, Int) -> Void)? = nil) async throws {
        guard destinationDirectoryURL.startAccessingSecurityScopedResource() else {
            throw BackupError.destinationInaccessible
        }
        defer { destinationDirectoryURL.stopAccessingSecurityScopedResource() }

        try await ensureFreeSpace(at: destinationDirectoryURL, sizeProvider: sizeProvider)

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationDirectoryURL.path) {
            try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        }
        let fileName = backupFileName(for: libraryName, fileExtension: "zip")
        let destinationURL = Self.uniqueURL(in: destinationDirectoryURL, fileName: fileName)
        do {
            try await writeFolderArchive(
                at: destinationURL,
                rootName: (fileName as NSString).deletingPathExtension,
                options: FolderBackupOptions(originalProvider: originalProvider, prefetch: prefetch,
                                             skipping: skipping, progress: progress)
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func writeFolderArchive(at url: URL, rootName: String,
                                    options: FolderBackupOptions) async throws {
        let progress = options.progress
        let skipping = options.skipping
        let albumPaths = albumFolderPaths(rootName: rootName)
        let pics = folderBackupPics()
        let writer = try ZIPArchiveWriter(url: url)
        try writer.addDirectory(rootName)
        for path in Set(albumPaths.values).sorted() {
            try writer.addDirectory(path)
        }

        var usedNames: [String: Set<String>] = [:]
        let total = pics.count
        await progress?(0, total)
        await options.prefetch?(pics.filter { !hasLocalOriginal($0) && !skipping.contains($0.id) }.map(\.id))
        for (index, pic) in pics.enumerated() {
            if skipping.contains(pic.id) {
                await progress?(index + 1, total)
                continue
            }
            let directory = pic.albumID.flatMap { albumPaths[$0] } ?? rootName
            guard let source = await originalSource(for: pic,
                                                    originalProvider: options.originalProvider) else {
                throw BackupError.originalUnavailable
            }
            let (sourceURL, sourceData) = (source.url, source.data)
            let isVideo = pic.mediaType == MediaType.video.rawValue
            let fileExtension = Self.fileExtension(forVideo: isVideo, filePath: pic.filePath,
                                                   localURL: sourceURL, data: sourceData)
            let fileName = Self.uniqueName(Self.sanitizedComponent(pic.name, fallback: pic.id),
                                           fileExtension: fileExtension,
                                           taken: &usedNames[directory, default: []])
            if let sourceURL {
                try writer.addFile("\(directory)/\(fileName)", contentsOf: sourceURL,
                                   modified: pic.dateAdded)
            } else if let sourceData {
                try writer.addFile("\(directory)/\(fileName)", data: sourceData,
                                   modified: pic.dateAdded)
            }
            await progress?(index + 1, total)
        }
        try writer.finish()
    }

    private func originalSource(
        for pic: FolderBackupPic,
        originalProvider: (@Sendable (String) async -> Data?)?
    ) async -> FolderBackupSource? {
        if hasLocalOriginal(pic), let path = pic.filePath {
            let localURL = pic.mediaType == MediaType.video.rawValue
                ? videoFileURL(forRelativePath: path)
                : imageFileURL(forRelativePath: path)
            return FolderBackupSource(url: localURL, data: nil)
        }
        guard let data = await originalProvider?(pic.id) else { return nil }
        return FolderBackupSource(url: nil, data: data)
    }

    private func hasLocalOriginal(_ pic: FolderBackupPic) -> Bool {
        guard let path = pic.filePath else { return false }
        let localURL = pic.mediaType == MediaType.video.rawValue
            ? videoFileURL(forRelativePath: path)
            : imageFileURL(forRelativePath: path)
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    // MARK: - Layout

    private func albumFolderPaths(rootName: String) -> [String: String] {
        var names: [String: String] = [:]
        var parents: [String: String] = [:]
        let query = albumsTable.select(albumId, albumName, albumParentId)
        for row in (try? database.safeRows(query)) ?? [] {
            let id = (try? row.get(albumId)) ?? ""
            guard !id.isEmpty else { continue }
            names[id] = Self.sanitizedComponent((try? row.get(albumName)) ?? "", fallback: id)
            if let parent = (try? row.get(albumParentId)) ?? nil, !parent.isEmpty {
                parents[id] = parent
            }
        }
        var children: [String: [String]] = [:]
        for id in names.keys {
            let parent = parents[id].flatMap { names[$0] != nil ? $0 : nil } ?? ""
            children[parent, default: []].append(id)
        }
        var paths: [String: String] = [:]
        var visited: Set<String> = []
        var pending: [(parent: String, prefix: String)] = [("", rootName)]
        while let level = pending.popLast() {
            var taken: Set<String> = []
            let sorted = (children[level.parent] ?? []).sorted { (names[$0] ?? "") < (names[$1] ?? "") }
            for id in sorted where !visited.contains(id) {
                visited.insert(id)
                let component = Self.uniqueName(names[id] ?? id, fileExtension: nil, taken: &taken)
                let path = "\(level.prefix)/\(component)"
                paths[id] = path
                pending.append((id, path))
            }
        }
        for id in names.keys where paths[id] == nil {
            paths[id] = rootName
        }
        return paths
    }

    private func folderBackupPics() -> [FolderBackupPic] {
        let query = picsTable
            .filter(picDateDeleted == nil)
            .select(picId, picName, picAlbumId, picMediaType, picFilePath, picDateAdded)
        return ((try? database.safeRows(query)) ?? []).map { row in
            FolderBackupPic(id: (try? row.get(picId)) ?? "",
                            name: (try? row.get(picName)) ?? "",
                            albumID: (try? row.get(picAlbumId)) ?? nil,
                            mediaType: (try? row.get(picMediaType)) ?? 0,
                            filePath: (try? row.get(picFilePath)) ?? nil,
                            dateAdded: Date(timeIntervalSince1970: (try? row.get(picDateAdded)) ?? 0))
        }
    }

    // MARK: - Naming

    private static func fileExtension(forVideo isVideo: Bool, filePath: String?,
                                      localURL: URL?, data: Data?) -> String {
        if isVideo {
            let stored = filePath.map { ($0 as NSString).pathExtension } ?? ""
            return stored.isEmpty ? "mov" : stored
        }
        let source = localURL.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            ?? data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        guard let source, let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              let fileExtension = type.preferredFilenameExtension else {
            return "png"
        }
        return fileExtension
    }

    private static func sanitizedComponent(_ name: String, fallback: String) -> String {
        let stripped = name.map { character -> Character in
            character == "/" || character == ":" || character.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }) ? "_" : character
        }
        let trimmed = String(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return fallback }
        return String(trimmed.prefix(120))
    }

    private static func uniqueName(_ stem: String, fileExtension: String?,
                                   taken: inout Set<String>) -> String {
        let base = (stem as NSString).deletingPathExtension.isEmpty
            ? stem : (stem as NSString).deletingPathExtension
        var candidate = fileExtension.map { "\(base).\($0)" } ?? base
        var suffix = 2
        while taken.contains(candidate.lowercased()) {
            candidate = fileExtension.map { "\(base) \(suffix).\($0)" } ?? "\(base) \(suffix)"
            suffix += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }
}
