import Engine
import SwiftUI

@MainActor @Observable
final class AlbumCoverCache {
    static let shared = AlbumCoverCache()

    struct CoverImages: Sendable {
        let primary: Image?
        let secondary: Image?
        let tertiary: Image?
        let id = UUID()
    }

    struct InvalidationToken: Equatable, Sendable {
        fileprivate let epoch: Int
        fileprivate let generation: Int
    }

    nonisolated(unsafe) private let cache = NSCache<NSString, CoverImagesBox>()

    /// Incremented each time new images are cached, causing observing views to re-check.
    private(set) var version: Int = 0

    /// Coalesces rapid version increments so SwiftUI doesn't re-evaluate every
    /// observing view once per loaded cover.
    @ObservationIgnored private var versionBumpPending = false

    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var inFlightLoads: [String: Task<Void, Never>] = [:]

    init() {
        cache.countLimit = 200
    }

    nonisolated func images(forAlbumID id: String) -> CoverImages? {
        cache.object(forKey: id as NSString)?.value
    }

    func invalidationToken(forAlbumID id: String) -> InvalidationToken {
        InvalidationToken(epoch: epoch, generation: generations[id, default: 0])
    }

    private func store(_ images: CoverImages, forAlbumID id: String, token: InvalidationToken) {
        guard token == invalidationToken(forAlbumID: id) else { return }
        cache.setObject(CoverImagesBox(images), forKey: id as NSString)
        scheduleVersionBump()
    }

    /// Coalesces multiple version bumps into a single update, reducing the number of
    /// SwiftUI view re-evaluations when many covers finish loading close together.
    private func scheduleVersionBump() {
        guard !versionBumpPending else { return }
        versionBumpPending = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.versionBumpPending = false
            self.version += 1
        }
    }

    func removeAllImages() {
        epoch += 1
        generations.removeAll()
        inFlightLoads.removeAll()
        cache.removeAllObjects()
        pendingDiskDeletions.removeAll()
        version += 1
    }

    func removeImages(forAlbumID id: String) {
        generations[id, default: 0] += 1
        inFlightLoads[id] = nil
        cache.removeObject(forKey: id as NSString)
        pendingDiskDeletions.insert(id)
        version += 1
        Task {
            await CoverCacheActor.shared.deleteCover(forAlbumWithID: id)
            _ = await MainActor.run {
                pendingDiskDeletions.remove(id)
            }
        }
    }

    /// Album IDs whose disk cache entries are being deleted asynchronously.
    /// `loadCover` skips the disk cache for these to avoid reloading stale data.
    @ObservationIgnored private var pendingDiskDeletions: Set<String> = []

    func loadCover(for album: Album) async {
        let albumID = album.id
        guard images(forAlbumID: albumID) == nil else { return }
        if let running = inFlightLoads[albumID] {
            await running.value
            return
        }
        let token = invalidationToken(forAlbumID: albumID)
        let skipDiskCache = pendingDiskDeletions.contains(albumID)
        let task = Task {
            let images = await Self.fetchCover(for: album, skipDiskCache: skipDiskCache)
            store(images, forAlbumID: albumID, token: token)
        }
        inFlightLoads[albumID] = task
        await task.value
        if inFlightLoads[albumID] == task {
            inFlightLoads[albumID] = nil
        }
    }

    @concurrent private nonisolated static func fetchCover(for album: Album, skipDiskCache: Bool) async -> CoverImages {
        let albumID = album.id
        let hasCover = album.hasCoverPhoto
        let versionKey = album.identifiableString()

        if !skipDiskCache,
           let cached = await CoverCacheActor.shared.cachedCover(
            forAlbumWithID: albumID, versionKey: versionKey
           ) {
            return decodeCoverImages(
                primary: cached.primary,
                secondary: cached.secondary,
                tertiary: cached.tertiary
            )
        }

        let dataBlobs = await coverDataBlobs(for: album, hasCover: hasCover, using: DataActor.shared)

        await CoverCacheActor.shared.storeCover(
            primary: dataBlobs[0], secondary: dataBlobs[1], tertiary: dataBlobs[2],
            forAlbumWithID: albumID, versionKey: versionKey
        )

        return decodeCoverImages(
            primary: dataBlobs[0], secondary: dataBlobs[1], tertiary: dataBlobs[2]
        )
    }

    private nonisolated static func coverDataBlobs(
        for album: Album, hasCover: Bool, using dataActor: DataActor
    ) async -> [Data?] {
        let thumbnails = await dataActor.representativeThumbnails(
            forAlbumWithID: album.id, limit: 3
        )
        var coverData: Data?
        if hasCover {
            coverData = await dataActor.albumCoverData(forAlbumWithID: album.id)
        }
        var dataBlobs: [Data?] = []
        if hasCover, let coverData {
            dataBlobs.append(coverData)
        }
        for data in thumbnails {
            if dataBlobs.count >= 3 { break }
            dataBlobs.append(data)
        }
        while dataBlobs.count < 3 { dataBlobs.append(nil) }
        return dataBlobs
    }

    /// Loads covers for a list of albums progressively, processing them in small
    /// batches to avoid saturating the database actors and main thread.
    nonisolated func loadCovers(for albums: [Album]) async {
        let maxConcurrent = 4
        await withTaskGroup(of: Void.self) { group in
            var iterator = albums.makeIterator()

            for _ in 0..<min(maxConcurrent, albums.count) {
                guard let album = iterator.next() else { break }
                group.addTask {
                    await self.loadCover(for: album)
                }
            }

            for await _ in group {
                if let album = iterator.next() {
                    group.addTask {
                        await self.loadCover(for: album)
                    }
                }
            }
        }
    }

    /// Loads covers for albums that live in a specific (possibly non-current) library,
    /// reading thumbnails through that library's DataActor and caching in memory only
    /// (the on-disk CoverCacheActor is per-current-library and must not be touched here).
    nonisolated func loadCovers(for albums: [Album], inLibrary libraryID: String) async {
        let dataActor = DataActor.instance(for: libraryID)
        let maxConcurrent = 4
        await withTaskGroup(of: Void.self) { group in
            var iterator = albums.makeIterator()
            for _ in 0..<min(maxConcurrent, albums.count) {
                guard let album = iterator.next() else { break }
                group.addTask { await self.loadCover(for: album, using: dataActor) }
            }
            for await _ in group {
                if let album = iterator.next() {
                    group.addTask { await self.loadCover(for: album, using: dataActor) }
                }
            }
        }
    }

    private func loadCover(for album: Album, using dataActor: DataActor) async {
        let albumID = album.id
        guard images(forAlbumID: albumID) == nil else { return }
        let token = invalidationToken(forAlbumID: albumID)
        let hasCover = album.hasCoverPhoto
        let dataBlobs = await Self.coverDataBlobs(for: album, hasCover: hasCover, using: dataActor)
        let images = await Self.decodeCoverImagesOffMain(dataBlobs)
        store(images, forAlbumID: albumID, token: token)
    }

    @concurrent private nonisolated static func decodeCoverImagesOffMain(_ dataBlobs: [Data?]) async -> CoverImages {
        decodeCoverImages(primary: dataBlobs[0], secondary: dataBlobs[1], tertiary: dataBlobs[2])
    }

    /// Decodes raw JPEG Data blobs into SwiftUI Images.
    /// Forces pixel decompression off the main thread so the render pass doesn't stall.
    private nonisolated static func decodeCoverImages(
        primary: Data?, secondary: Data?, tertiary: Data?
    ) -> CoverImages {
        CoverImages(
            primary: primary.flatMap { decodedImage(from: $0) },
            secondary: secondary.flatMap { decodedImage(from: $0) },
            tertiary: tertiary.flatMap { decodedImage(from: $0) }
        )
    }

    /// Decodes JPEG data into a SwiftUI Image with pixels fully decompressed.
    /// By drawing through UIGraphicsImageRenderer, the backing CGImage is forced
    /// to decode immediately rather than lazily during the first render on the main thread.
    private nonisolated static func decodedImage(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = uiImage.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: uiImage.size, format: format)
        let decoded = renderer.image { _ in
            uiImage.draw(at: .zero)
        }
        return Image(uiImage: decoded)
    }
}

/// Wrapper so CoverImages can be stored in NSCache.
private final class CoverImagesBox: Sendable {
    let value: AlbumCoverCache.CoverImages
    init(_ value: AlbumCoverCache.CoverImages) { self.value = value }
}
