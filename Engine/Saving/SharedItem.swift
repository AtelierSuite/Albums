import UIKit
import UniformTypeIdentifiers

public enum SharedItem: Sendable {
    case image(Data)
    case video(URL)

    public var imageData: Data? {
        if case .image(let data) = self { return data }
        return nil
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
            return await data(from: provider, type: .image).map { .image($0) }
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
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
