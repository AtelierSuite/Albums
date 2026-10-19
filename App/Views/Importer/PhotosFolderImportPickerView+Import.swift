import Engine
import Photos
import SwiftUI

extension PhotosFolderImportPickerView {

    func startFolderImport(_ folder: PHCollectionList) {
        isImporting = true
        importTotalCount = countImagesRecursively(in: folder)
        importCurrentCount = 0

        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            let folderName = folder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import")
            let rootAlbum = await DataActor.shared.createAlbum(
                folderName, parentAlbumID: selectedAlbum?.id
            )

            await importFolderRecursively(folder, parentAlbumID: rootAlbum.id)

            await MainActor.run {
                if let selectedAlbum {
                    AlbumCoverCache.shared.removeImages(forAlbumID: selectedAlbum.id)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                importCompletedCount = importCurrentCount
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                doWithAnimation {
                    isImportCompleted = true
                }
            }
        }
    }

    func importFolderRecursively(_ folder: PHCollectionList, parentAlbumID: String) async {
        let result = PHCollection.fetchCollections(in: folder, options: nil)
        var albums: [PHAssetCollection] = []
        var subfolders: [PHCollectionList] = []

        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                albums.append(album)
            } else if let subfolder = collection as? PHCollectionList {
                subfolders.append(subfolder)
            }
        }

        for album in albums {
            let albumName = album.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import")
            let childAlbum = await DataActor.shared.createAlbum(albumName, parentAlbumID: parentAlbumID)
            await importPhotosFromAlbum(album, intoAlbumID: childAlbum.id)
        }

        for subfolder in subfolders {
            let subfolderName = subfolder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import")
            let childAlbum = await DataActor.shared.createAlbum(subfolderName, parentAlbumID: parentAlbumID)
            await importFolderRecursively(subfolder, parentAlbumID: childAlbum.id)
        }
    }

    func importPhotosFromAlbum(_ collection: PHAssetCollection, intoAlbumID albumID: String) async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assetResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        var assets: [PHAsset] = []
        assetResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? Pic.newFilename()

            if asset.mediaType == .video {
                await importVideoAsset(asset, filename: filename, albumID: albumID)
            } else {
                let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    imageManager.requestImageDataAndOrientation(
                        for: asset, options: requestOptions
                    ) { data, _, _, _ in
                        continuation.resume(returning: data)
                    }
                }

                if let data {
                    await DataActor.shared.createPic(
                        filename, data: data,
                        inAlbumWithID: albumID,
                        dateAdded: asset.creationDate
                    )
                }
            }

            await MainActor.run {
                importCurrentCount += 1
            }
        }
    }

    private func importVideoAsset(_ asset: PHAsset, filename: String, albumID: String) async {
        let videoRequestOptions = PHVideoRequestOptions()
        videoRequestOptions.isNetworkAccessAllowed = true
        videoRequestOptions.deliveryMode = .highQualityFormat

        let exportSession: AVAssetExportSession? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestExportSession(
                forVideo: asset,
                options: videoRequestOptions,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                nonisolated(unsafe) let result = session
                continuation.resume(returning: result)
            }
        }

        guard let exportSession else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard (try? await exportSession.export(to: tempURL, as: .mov)) != nil,
              let videoData = try? Data(contentsOf: tempURL) else { return }

        let fileExtension = (filename as NSString).pathExtension.isEmpty
            ? "mov" : (filename as NSString).pathExtension.lowercased()

        await DataActor.shared.createVideo(
            filename,
            data: videoData,
            duration: asset.duration,
            fileExtension: fileExtension,
            inAlbumWithID: albumID,
            dateAdded: asset.creationDate
        )
    }
}
