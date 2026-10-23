import UIKit
import UniformTypeIdentifiers

public enum SharedItem: Sendable {
    case image(Data)
    case video(URL)

    public var imageData: Data? {
        if case .image(let data) = self { return data }
        return nil
    }

    private static var temporaryCopiesDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SharedItems", isDirectory: true)
    }

    public static func removeTemporaryCopies() {
        try? FileManager.default.removeItem(at: temporaryCopiesDirectory)
    }

    @MainActor
    public static func load(from context: NSExtensionContext?) async -> (items: [SharedItem], failedCount: Int) {
        let providers = (context?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        var items: [SharedItem] = []
        var failedCount = 0
        for provider in providers {
            if let item = await load(provider) {
                items.append(item)
            } else {
                failedCount += 1
            }
        }
        return (items, failedCount)
    }

    @MainActor
    private static func load(_ provider: NSItemProvider) async -> SharedItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await fileCopy(from: provider, type: .movie).map { .video($0) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await imageData(from: provider).map { .image($0) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await url(from: provider),
           let (data, _) = try? await URLSession.shared.data(from: url),
           UIImage(data: data) != nil {
            return .image(data)
        }
        return nil
    }

    @MainActor
    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    private static func imageData(from provider: NSItemProvider) async -> Data? {
        let types = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .filter { $0.conforms(to: .image) && $0 != .image } + [.image]
        var firstData: Data?
        for type in types {
            guard let data = await data(from: provider, type: type) else { continue }
            if UIImage(data: data) != nil { return data }
            firstData = firstData ?? data
        }
        if let data = await itemImageData(from: provider) {
            return data
        }
        return firstData
    }

    // Apps like X register an image type backed by a UIImage or file URL whose data representation isn't image data.
    @MainActor
    private static func itemImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                let data: Data? = switch item {
                case let image as UIImage: image.jpegData(compressionQuality: 0.95) ?? image.pngData()
                case let url as URL: try? Data(contentsOf: url)
                case let data as Data: data
                default: nil
                }
                continuation.resume(returning: data.flatMap { UIImage(data: $0) != nil ? $0 : nil })
            }
        }
    }

    @MainActor
    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // The URL handed to the completion handler is deleted as soon as it returns.
    @MainActor
    private static func fileCopy(from provider: NSItemProvider, type: UTType) async -> URL? {
        let copiesDirectory = temporaryCopiesDirectory
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let directory = copiesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let copy = directory.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
