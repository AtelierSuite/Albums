import Photos
import UIKit

@MainActor @Observable
final class LibraryCoverCache {
    static let shared = LibraryCoverCache()
    nonisolated static let photosLibraryID = "__photos__"
    nonisolated static let maximumCoverCount = 4

    struct Summary: Sendable {
        let images: [UIImage]
        let picCount: Int
        let albumCount: Int
    }

    private(set) var summaries: [String: Summary] = [:]

    func summary(for libraryID: String) -> Summary? {
        summaries[libraryID]
    }

    func reload(_ libraries: [PicLibrary]) async {
        await withTaskGroup(of: (String, Summary).self) { group in
            for library in libraries {
                let libraryID = library.id
                group.addTask {
                    (libraryID, await Self.loadSummary(for: libraryID))
                }
            }
            for await (libraryID, summary) in group {
                summaries[libraryID] = summary
            }
        }
    }

    func reloadPhotosLibrary(targetLength: CGFloat) async {
        summaries[Self.photosLibraryID] = await Self.loadPhotosSummary(targetLength: targetLength)
    }

    nonisolated static func loadSummary(for libraryID: String) async -> Summary {
        let dataActor = DataActor.instance(for: libraryID)
        let coverPicIDs = await LibrariesActor.shared.coverPicIDs(forID: libraryID)
        var thumbnails = await dataActor.thumbnails(forPicIDs: coverPicIDs)
        if thumbnails.isEmpty {
            thumbnails = await dataActor.recentThumbnails(limit: maximumCoverCount)
        }
        let images = thumbnails.prefix(maximumCoverCount).compactMap { UIImage(data: $0) }
        return Summary(images: images,
                       picCount: await dataActor.picCount(),
                       albumCount: await dataActor.albumCount())
    }

    nonisolated static func loadPhotosSummary(targetLength: CGFloat) async -> Summary? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        var recentAssets: [PHAsset] = []
        assets.enumerateObjects { asset, index, stop in
            recentAssets.append(asset)
            if index + 1 >= maximumCoverCount { stop.pointee = true }
        }
        var images: [UIImage] = []
        for asset in recentAssets {
            if let image = await requestImage(for: asset, targetLength: targetLength) {
                images.append(image)
            }
        }
        let albumCount = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).count
        return Summary(images: images, picCount: assets.count, albumCount: albumCount)
    }

    private nonisolated static func requestImage(for asset: PHAsset, targetLength: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetLength, height: targetLength),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
