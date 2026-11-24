import CoreTransferable
import Engine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum Drop: Transferable {
    case album(AlbumTransferable)
    case pic(PicTransferable)
    case file(URL)
    case importedPhoto(Image)

    static let acceptedContentTypes: [UTType] = [.album, .picture, .image, .movie, .url, .fileURL]

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { Drop.album($0) }
        ProxyRepresentation { Drop.pic($0) }
        // Browsers also offer the image's web URL, which may need auth (e.g. Pixiv), so prefer the dragged bytes.
        FileRepresentation(importedContentType: .image) { received in
            Drop.file(try tempCopy(of: received.file))
        }
        FileRepresentation(importedContentType: .movie) { received in
            Drop.file(try tempCopy(of: received.file))
        }
        ProxyRepresentation { Drop.file($0) }
        ProxyRepresentation { Drop.importedPhoto($0) }
    }

    var album: AlbumTransferable? {
        if case .album(let album) = self { return album }
        return nil
    }

    var pic: PicTransferable? {
        if case .pic(let pic) = self { return pic }
        return nil
    }

    var file: URL? {
        if case .file(let url) = self { return url }
        return nil
    }

    var importedPhoto: Image? {
        if case .importedPhoto(let importedPhoto) = self { return importedPhoto }
        return nil
    }

    @MainActor
    static func load(from providers: [NSItemProvider]) async -> [Drop] {
        var drops: [Drop] = []
        for provider in providers {
            guard let drop = await loadDrop(from: provider) else { continue }
            if case .file(let fileURL) = drop, fileURL.isFileURL,
               let webURL = await loadWebURL(from: provider) {
                drops.append(.file(renamed(fileURL, toImageNameIn: webURL)))
            } else {
                drops.append(drop)
            }
        }
        return drops
    }

    @MainActor
    private static func loadDrop(from provider: NSItemProvider) async -> Drop? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: Drop.self) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    @MainActor
    private static func loadWebURL(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        let url: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    private static func renamed(_ fileURL: URL, toImageNameIn webURL: URL) -> URL {
        let name = webURL.lastPathComponent
        guard let webType = UTType(filenameExtension: webURL.pathExtension), webType.conforms(to: .image),
              let fileType = UTType(filenameExtension: fileURL.pathExtension), fileType.conforms(to: .image),
              name != fileURL.lastPathComponent
        else { return fileURL }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        guard (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil else { return fileURL }
        return destination
    }

    private static func tempCopy(of source: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }
}

extension View {
    func dropDestination(forDrops action: @escaping @MainActor ([Drop]) -> Void) -> some View {
        onDrop(of: Drop.acceptedContentTypes, isTargeted: nil) { providers in
            Task { @MainActor in
                let drops = await Drop.load(from: providers)
                if !drops.isEmpty { action(drops) }
            }
            return true
        }
    }
}
