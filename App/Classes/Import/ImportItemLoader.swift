import AVFoundation
import CoreTransferable
import Engine
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

nonisolated enum ImportItemLoader {

    static func canReadPhotoLibrary() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func importItem(
        _ item: ImportItem,
        jobID: UUID,
        into dataActor: DataActor,
        pickerItem: PhotosPickerItem?,
        canReadLibrary: Bool
    ) async -> String? {
        switch item.source {
        case .photosAsset(let localIdentifier, let isVideo):
            let asset = canReadLibrary ? fetchAsset(localIdentifier) : nil
            if let pickerItem {
                return await importPickerItem(
                    pickerItem, asset: asset, isVideo: isVideo, item: item, into: dataActor
                )
            }
            guard let asset else { return nil }
            return await importAsset(asset, item: item, into: dataActor)
        case .stagedFile(let name, let originalFilename):
            let url = ImportJobStore.stagedFileURL(named: name, for: jobID)
            return await importStagedFile(
                at: url, originalFilename: originalFilename, item: item, into: dataActor
            )
        }
    }

    private static func fetchAsset(_ localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private static func originalFilename(of asset: PHAsset?) -> String? {
        guard let asset else { return nil }
        return PHAssetResource.assetResources(for: asset).first?.originalFilename
    }

    private static func importPickerItem(
        _ pickerItem: PhotosPickerItem,
        asset: PHAsset?,
        isVideo: Bool,
        item: ImportItem,
        into dataActor: DataActor
    ) async -> String? {
        let dateAdded = item.dateAdded ?? asset?.creationDate
        if isVideo {
            guard let picked = try? await pickerItem.loadTransferable(type: PickedVideoFile.self) else {
                return nil
            }
            defer { try? FileManager.default.removeItem(at: picked.url) }
            return await createVideo(
                from: picked.url,
                filename: originalFilename(of: asset) ?? Pic.newVideoFilename(),
                duration: nil,
                item: ImportItem(source: item.source, albumID: item.albumID, dateAdded: dateAdded),
                into: dataActor
            )
        }
        guard let data = try? await pickerItem.loadTransferable(type: Data.self) else { return nil }
        return await dataActor.createPic(
            originalFilename(of: asset) ?? Pic.newFilename(), data: data,
            inAlbumWithID: item.albumID, dateAdded: dateAdded
        )
    }

    private static func importAsset(
        _ asset: PHAsset, item: ImportItem, into dataActor: DataActor
    ) async -> String? {
        let dateAdded = item.dateAdded ?? asset.creationDate
        if asset.mediaType == .video {
            guard let url = await exportVideo(asset) else { return nil }
            defer { try? FileManager.default.removeItem(at: url) }
            return await createVideo(
                from: url,
                filename: originalFilename(of: asset) ?? Pic.newVideoFilename(),
                duration: asset.duration,
                item: ImportItem(source: item.source, albumID: item.albumID, dateAdded: dateAdded),
                into: dataActor
            )
        }
        guard let data = await imageData(for: asset) else { return nil }
        return await dataActor.createPic(
            originalFilename(of: asset) ?? Pic.newFilename(), data: data,
            inAlbumWithID: item.albumID, dateAdded: dateAdded
        )
    }

    private static func importStagedFile(
        at url: URL, originalFilename: String, item: ImportItem, into dataActor: DataActor
    ) async -> String? {
        let uti = UTType(filenameExtension: url.pathExtension)
        if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
            return await createVideo(
                from: url, filename: originalFilename, duration: nil, item: item, into: dataActor
            )
        }
        guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else { return nil }
        return await dataActor.createPic(
            originalFilename, data: data, inAlbumWithID: item.albumID, dateAdded: item.dateAdded
        )
    }

    private static func createVideo(
        from url: URL,
        filename: String,
        duration: TimeInterval?,
        item: ImportItem,
        into dataActor: DataActor
    ) async -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let resolvedDuration: TimeInterval
        if let duration {
            resolvedDuration = duration
        } else {
            resolvedDuration = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0
        }
        let nameExtension = (filename as NSString).pathExtension.lowercased()
        let fileExtension = nameExtension.isEmpty
            ? (url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())
            : nameExtension
        return await dataActor.createVideo(
            filename,
            data: data,
            duration: resolvedDuration,
            fileExtension: fileExtension,
            inAlbumWithID: item.albumID,
            dateAdded: item.dateAdded
        )
    }

    private static func imageData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func exportVideo(_ asset: PHAsset) async -> URL? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let exportSession: AVAssetExportSession? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestExportSession(
                forVideo: asset,
                options: options,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                nonisolated(unsafe) let result = session
                continuation.resume(returning: result)
            }
        }
        guard let exportSession else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard (try? await exportSession.export(to: url, as: .mov)) != nil else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}

nonisolated struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try? FileManager.default.removeItem(at: copyURL)
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return Self(url: copyURL)
        }
    }
}
