import Engine
import Photos
import PhotosUI
import SwiftUI

extension AlbumView {

    func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        importPickerItems(items, isVideo: false) {
            selectedPhotoItems = []
        }
    }

    func importSelectedVideos(_ items: [PhotosPickerItem]) {
        importPickerItems(items, isVideo: true) {
            selectedVideoItems = []
        }
    }

    private func importPickerItems(
        _ items: [PhotosPickerItem], isVideo: Bool, onCompletion: @escaping () -> Void
    ) {
        let albumID = currentAlbum?.id
        var job = makeImportJob(for: currentAlbum)
        var pickerItems: [String: PhotosPickerItem] = [:]
        for item in items {
            let identifier = item.itemIdentifier ?? UUID().uuidString
            pickerItems[identifier] = item
            job.items.append(ImportItem(
                source: .photosAsset(localIdentifier: identifier, isVideo: isVideo), albumID: albumID
            ))
        }
        isImportingPhotos = true
        Task {
            await requestPhotosMetadataAccess()
            _ = await ImportManager.shared.run(job, pickerItems: pickerItems)
            onCompletion()
            isImportingPhotos = false
        }
    }

    private func requestPhotosMetadataAccess() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }

    func importLoadedFiles(_ files: [(filename: String, data: Data)]) {
        let job = makeImportJob(for: currentAlbum)
        isImportingPhotos = true
        Task {
            let staged = await Self.stage(files: files, for: job, albumID: job.destinationAlbumID)
            _ = await ImportManager.shared.run(staged)
            isImportingPhotos = false
        }
    }

    func importDroppedImages(_ images: [Image], into album: Album? = nil) {
        let job = makeImportJob(for: album ?? currentAlbum)
        isImportingPhotos = true
        Task {
            var files: [(filename: String, data: Data)] = []
            for image in images {
                if let data = image.render()?.data() {
                    files.append((filename: Pic.newFilename(), data: data))
                }
            }
            let staged = await Self.stage(files: files, for: job, albumID: job.destinationAlbumID)
            _ = await ImportManager.shared.run(staged)
            isImportingPhotos = false
        }
    }

    func importFiles(_ urls: [URL], into album: Album? = nil) {
        let job = makeImportJob(for: album ?? currentAlbum)
        isImportingPhotos = true
        Task {
            let staged = await Self.stage(urls: urls, for: job, albumID: job.destinationAlbumID)
            _ = await ImportManager.shared.run(staged)
            isImportingPhotos = false
        }
    }

    private func makeImportJob(for album: Album?) -> ImportJob {
        ImportJob(
            libraryID: DataActor.shared.collectionID,
            destinationAlbumID: album?.id,
            destinationAlbumName: album?.name
        )
    }

    private nonisolated static func stage(
        files: [(filename: String, data: Data)], for job: ImportJob, albumID: String?
    ) async -> ImportJob {
        var job = job
        for file in files {
            let pathExtension = (file.filename as NSString).pathExtension
            guard let name = try? ImportJobStore.stageData(file.data, for: job.id, pathExtension: pathExtension)
            else { continue }
            job.items.append(ImportItem(
                source: .stagedFile(name: name, originalFilename: file.filename), albumID: albumID
            ))
        }
        return job
    }

    private nonisolated static func stage(urls: [URL], for job: ImportJob, albumID: String?) async -> ImportJob {
        var job = job
        for fileURL in urls {
            if !fileURL.isFileURL {
                guard let (data, _) = try? await URLSession.shared.data(from: fileURL),
                      UIImage(data: data) != nil,
                      let name = try? ImportJobStore.stageData(data, for: job.id, pathExtension: fileURL.pathExtension)
                else { continue }
                job.items.append(ImportItem(
                    source: .stagedFile(name: name, originalFilename: fileURL.lastPathComponent), albumID: albumID
                ))
                continue
            }
            let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() }
            }
            guard let name = try? ImportJobStore.stageFile(at: fileURL, for: job.id) else { continue }
            job.items.append(ImportItem(
                source: .stagedFile(name: name, originalFilename: fileURL.lastPathComponent), albumID: albumID
            ))
        }
        cleanUpTempDropFiles(urls)
        return job
    }

    private nonisolated static func cleanUpTempDropFiles(_ urls: [URL]) {
        let tempBase = FileManager.default.temporaryDirectory.standardized
        for fileURL in urls {
            let parent = fileURL.deletingLastPathComponent().standardized
            if parent.path.hasPrefix(tempBase.path), parent.path != tempBase.path {
                try? FileManager.default.removeItem(at: parent)
            }
        }
    }
}
