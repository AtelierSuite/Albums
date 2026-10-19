import AVFoundation
import Engine
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

extension AlbumView {

    func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        isImportingPhotos = true
        importTotalCount = items.count
        importCurrentCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            let canUseMetadata = await requestPhotosMetadataAccess()
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let metadata = canUseMetadata ? assetMetadata(for: item) : nil
                    await DataActor.shared.createPic(metadata?.filename ?? Pic.newFilename(), data: data,
                                                     inAlbumWithID: currentAlbum?.id,
                                                     dateAdded: metadata?.creationDate)
                }
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            let count = items.count
            await sendImportNotification(count: count, albumName: currentAlbum?.name)
            await MainActor.run {
                if let currentAlbum {
                    AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                selectedPhotoItems = []
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isImportingPhotos = false
            }
        }
    }

    func importSelectedVideos(_ items: [PhotosPickerItem]) {
        isImportingPhotos = true
        importTotalCount = items.count
        importCurrentCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            let canUseMetadata = await requestPhotosMetadataAccess()
            for item in items {
                let metadata = canUseMetadata ? assetMetadata(for: item) : nil
                await importVideoFromPicker(
                    item,
                    filename: metadata?.filename ?? Pic.newVideoFilename(),
                    creationDate: metadata?.creationDate
                )
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            let count = items.count
            await sendImportNotification(count: count, albumName: currentAlbum?.name)
            await MainActor.run {
                if let currentAlbum {
                    AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                selectedVideoItems = []
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isImportingPhotos = false
            }
        }
    }

    private func importVideoFromPicker(
        _ item: PhotosPickerItem,
        filename: String,
        creationDate: Date?
    ) async {
        guard let picked = try? await item.loadTransferable(type: PickedVideoFile.self) else { return }
        let tempURL = picked.url
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        guard let videoData = try? Data(contentsOf: tempURL) else { return }

        let nameExtension = (filename as NSString).pathExtension.lowercased()
        let fileExtension = nameExtension.isEmpty
            ? (tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension.lowercased())
            : nameExtension

        await DataActor.shared.createVideo(
            filename,
            data: videoData,
            duration: duration,
            fileExtension: fileExtension,
            inAlbumWithID: currentAlbum?.id,
            dateAdded: creationDate
        )
    }

    /// Requests read/write Photos access up front so the system prompt appears at a deliberate moment
    /// (when an import starts) rather than unexpectedly mid-import. Returns whether asset metadata may
    /// be read; if not, callers fall back to generated filenames.
    private func requestPhotosMetadataAccess() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized || status == .limited
    }

    /// Reads the original filename and creation date for a picked item from the Photos library.
    /// Only call when access has been granted, as it touches `PHAsset` directly.
    private func assetMetadata(for item: PhotosPickerItem) -> (filename: String?, creationDate: Date?)? {
        guard let identifier = item.itemIdentifier else { return nil }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename
        return (filename, asset.creationDate)
    }

    func importLoadedFiles(_ files: [(filename: String, data: Data)]) {
        isImportingPhotos = true
        importTotalCount = files.count
        importCurrentCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            for file in files {
                let uti = UTType(filenameExtension: (file.filename as NSString).pathExtension)
                if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
                    let ext = (file.filename as NSString).pathExtension.lowercased()
                    await DataActor.shared.createVideo(
                        file.filename, data: file.data, duration: 0,
                        fileExtension: ext.isEmpty ? "mov" : ext,
                        inAlbumWithID: currentAlbum?.id
                    )
                } else {
                    await DataActor.shared.createPic(file.filename, data: file.data,
                                                     inAlbumWithID: currentAlbum?.id)
                }
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            let count = files.count
            await sendImportNotification(count: count, albumName: currentAlbum?.name)
            await MainActor.run {
                if let currentAlbum {
                    AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isImportingPhotos = false
            }
        }
    }

    func importDroppedImages(_ images: [Image], into album: Album? = nil) {
        let targetAlbum = album ?? currentAlbum
        let targetAlbumID = targetAlbum?.id
        let targetAlbumName = targetAlbum?.name
        isImportingPhotos = true
        importTotalCount = images.count
        importCurrentCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            var importedCount = 0
            for image in images {
                let data = await MainActor.run { image.render()?.data() }
                if let data {
                    await DataActor.shared.createPic(Pic.newFilename(), data: data,
                                                     inAlbumWithID: targetAlbumID)
                    importedCount += 1
                }
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            await sendImportNotification(count: importedCount, albumName: targetAlbumName)
            await MainActor.run {
                if let targetAlbumID {
                    AlbumCoverCache.shared.removeImages(forAlbumID: targetAlbumID)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isImportingPhotos = false
            }
        }
    }

    // swiftlint:disable:next function_body_length
    func importFiles(_ urls: [URL], into album: Album? = nil) {
        let targetAlbum = album ?? currentAlbum
        let targetAlbumID = targetAlbum?.id
        let targetAlbumName = targetAlbum?.name
        isImportingPhotos = true
        importTotalCount = urls.count
        importCurrentCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            var loadedImageFiles: [(filename: String, data: Data)] = []
            // swiftlint:disable:next large_tuple
            var loadedVideoFiles: [(filename: String, data: Data, duration: TimeInterval)] = []
            for fileURL in urls {
                let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let uti = UTType(filenameExtension: fileURL.pathExtension)
                if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
                    let asset = AVURLAsset(url: fileURL)
                    let duration = (try? await asset.load(.duration))?.seconds ?? 0
                    loadedVideoFiles.append((filename: fileURL.lastPathComponent, data: data, duration: duration))
                } else if UIImage(data: data) != nil {
                    loadedImageFiles.append((filename: fileURL.lastPathComponent, data: data))
                }
            }
            cleanUpTempDropFiles(urls)
            for file in loadedImageFiles {
                await DataActor.shared.createPic(file.filename, data: file.data,
                                                 inAlbumWithID: targetAlbumID)
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            for file in loadedVideoFiles {
                let ext = (file.filename as NSString).pathExtension.lowercased()
                await DataActor.shared.createVideo(
                    file.filename, data: file.data, duration: file.duration,
                    fileExtension: ext.isEmpty ? "mov" : ext,
                    inAlbumWithID: targetAlbumID
                )
                await MainActor.run {
                    importCurrentCount += 1
                }
            }
            let count = loadedImageFiles.count + loadedVideoFiles.count
            await sendImportNotification(count: count, albumName: targetAlbumName)
            await MainActor.run {
                if let targetAlbumID {
                    AlbumCoverCache.shared.removeImages(forAlbumID: targetAlbumID)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isImportingPhotos = false
            }
        }
    }

    private nonisolated func cleanUpTempDropFiles(_ urls: [URL]) {
        let tempBase = FileManager.default.temporaryDirectory.standardized
        for fileURL in urls {
            let parent = fileURL.deletingLastPathComponent().standardized
            if parent.path.hasPrefix(tempBase.path), parent.path != tempBase.path {
                try? FileManager.default.removeItem(at: parent)
            }
        }
    }

    private func sendImportNotification(count: Int, albumName: String?) async {
        guard showImportNotification else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        let freshStatus = await center.notificationSettings().authorizationStatus
        guard freshStatus == .authorized || freshStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "ViewTitle.Import")
        if count == 0 {
            content.body = String(localized: "Import.Notification.Empty", table: "Import")
        } else if let albumName {
            content.body = String(localized: "Import.Notification.Body.\(count).\(albumName)", table: "Import")
        } else {
            content.body = String(localized: "Import.Completed.Text.\(count)", table: "Import")
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

/// Loads a picked video out-of-process into a temporary file, so video import works without
/// requiring Photos library authorization.
private struct PickedVideoFile: Transferable {
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
