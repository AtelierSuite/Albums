import Engine
import Foundation

extension Notification.Name {
    static let libraryMoveProgress = Notification.Name("LibraryMoveProgress")
}

enum LibraryMoveError: Error {
    case sameLibrary
    case sourceMissing
    case idCollision
    case originalsNotUploaded
    case transferFailed
}

actor LibraryMoveManager {

    static let shared = LibraryMoveManager()

    func moveAlbum(albumID: String, from sourceID: String, to destinationID: String,
                   destinationParentAlbumID: String?) async throws {
        guard sourceID != destinationID else { throw LibraryMoveError.sameLibrary }
        let sourceActor = DataActor.instance(for: sourceID)
        let destActor = DataActor.instance(for: destinationID)

        let subtree = await sourceActor.collectSubtree(forAlbumID: albumID)
        try await assertNoCollision(albumIDs: subtree.albumIDs, picIDs: subtree.picIDs, in: destActor)

        let sourceIsICloud = await LibrariesActor.shared.isSyncEnabled(id: sourceID)
        let destIsICloud = await LibrariesActor.shared.isSyncEnabled(id: destinationID)
        try await assertOriginalsUploaded(picIDs: subtree.picIDs, sourceID: sourceID,
                                          sourceIsICloud: sourceIsICloud)

        var albumPlan: [(AlbumMoveRecord, String?)] = []
        var prefsPlan: [AlbumPreferences] = []
        for id in subtree.albumIDs {
            guard let record = await sourceActor.albumRecordForMove(id: id) else {
                throw LibraryMoveError.sourceMissing
            }
            let newParent = id == albumID ? destinationParentAlbumID : record.parentAlbumID
            albumPlan.append((record, newParent))
            if let prefs = await sourceActor.storedPreferences(forAlbumWithID: id) {
                prefsPlan.append(prefs)
            }
        }

        var picPlan: [(PicMoveRecord, String?)] = []
        for id in subtree.picIDs {
            guard let record = await sourceActor.picRecordForMove(id: id) else {
                throw LibraryMoveError.sourceMissing
            }
            picPlan.append((record, record.albumID))
        }

        try await performMove(
            albumPlan: albumPlan, prefsPlan: prefsPlan, picPlan: picPlan,
            sourceID: sourceID, destinationID: destinationID,
            sourceIsICloud: sourceIsICloud, destIsICloud: destIsICloud,
            sourceActor: sourceActor, destActor: destActor,
            sourceCleanup: { await sourceActor.deleteAlbumAndContents(withID: albumID) }
        )
    }

    func movePics(picIDs: [String], from sourceID: String, to destinationID: String,
                  destinationAlbumID: String?) async throws {
        guard sourceID != destinationID else { throw LibraryMoveError.sameLibrary }
        guard !picIDs.isEmpty else { return }
        let sourceActor = DataActor.instance(for: sourceID)
        let destActor = DataActor.instance(for: destinationID)

        try await assertNoCollision(albumIDs: [], picIDs: picIDs, in: destActor)

        let sourceIsICloud = await LibrariesActor.shared.isSyncEnabled(id: sourceID)
        let destIsICloud = await LibrariesActor.shared.isSyncEnabled(id: destinationID)
        try await assertOriginalsUploaded(picIDs: picIDs, sourceID: sourceID,
                                          sourceIsICloud: sourceIsICloud)

        var picPlan: [(PicMoveRecord, String?)] = []
        for id in picIDs {
            guard let record = await sourceActor.picRecordForMove(id: id) else {
                throw LibraryMoveError.sourceMissing
            }
            picPlan.append((record, destinationAlbumID))
        }

        try await performMove(
            albumPlan: [], prefsPlan: [], picPlan: picPlan,
            sourceID: sourceID, destinationID: destinationID,
            sourceIsICloud: sourceIsICloud, destIsICloud: destIsICloud,
            sourceActor: sourceActor, destActor: destActor,
            sourceCleanup: { await sourceActor.deletePics(withIDs: picIDs) }
        )
    }

    // MARK: - Guards

    private func assertNoCollision(albumIDs: [String], picIDs: [String], in destActor: DataActor) async throws {
        let collidingAlbums = await destActor.existingAlbumIDs(among: albumIDs)
        let collidingPics = await destActor.existingPicIDs(among: picIDs)
        if !collidingAlbums.isEmpty || !collidingPics.isEmpty {
            throw LibraryMoveError.idCollision
        }
    }

    private func assertOriginalsUploaded(picIDs: [String], sourceID: String,
                                         sourceIsICloud: Bool) async throws {
        guard sourceIsICloud else { return }
        let pending = await OriginalsManager.shared.pendingUploadPicIDs(picIDs: picIDs, in: sourceID)
        if !pending.isEmpty { throw LibraryMoveError.originalsNotUploaded }
    }

    // MARK: - Pipeline

    // swiftlint:disable:next function_parameter_count
    private func performMove(
        albumPlan: [(AlbumMoveRecord, String?)],
        prefsPlan: [AlbumPreferences],
        picPlan: [(PicMoveRecord, String?)],
        sourceID: String, destinationID: String,
        sourceIsICloud: Bool, destIsICloud: Bool,
        sourceActor: DataActor, destActor: DataActor,
        sourceCleanup: () async -> Void
    ) async throws {
        var insertedAlbumIDs: [String] = []
        var insertedPicIDs: [String] = []
        var movedCloudPics: [(String, MediaType)] = []

        func rollback() async {
            for (picID, mediaType) in movedCloudPics {
                await OriginalsManager.shared.moveCloudOriginal(
                    picID: picID, mediaType: mediaType, from: destinationID, to: sourceID)
            }
            await destActor.deleteMovedRecords(albumIDs: insertedAlbumIDs, picIDs: insertedPicIDs)
        }

        for (record, newParent) in albumPlan {
            await destActor.insertMovedAlbum(record, parentAlbumID: newParent)
            insertedAlbumIDs.append(record.id)
        }
        for prefs in prefsPlan {
            await destActor.insertPreferencesForMigration(prefs)
        }

        await postProgress(completed: 0, total: picPlan.count)
        for (record, newAlbumID) in picPlan {
            guard let relocation = await relocatePic(
                record, sourceID: sourceID, destinationID: destinationID,
                sourceIsICloud: sourceIsICloud, destIsICloud: destIsICloud,
                sourceActor: sourceActor, destActor: destActor
            ) else {
                await rollback()
                throw LibraryMoveError.transferFailed
            }
            await destActor.insertMovedPic(record, albumID: newAlbumID,
                                           filePath: relocation.filePath,
                                           originalSynced: relocation.originalSynced)
            insertedPicIDs.append(record.id)
            if relocation.movedCloud {
                movedCloudPics.append((record.id, record.resolvedMediaType))
            }
            await postProgress(completed: insertedPicIDs.count, total: picPlan.count)
        }

        let albumIDs = albumPlan.map { $0.0.id }
        let picIDs = picPlan.map { $0.0.id }
        let albumsOK = (await destActor.existingAlbumIDs(among: albumIDs)).count == albumIDs.count
        let picsOK = (await destActor.existingPicIDs(among: picIDs)).count == picIDs.count
        guard albumsOK && picsOK else {
            await rollback()
            throw LibraryMoveError.transferFailed
        }

        await sourceCleanup()
        await SpotlightIndexer.shared.scheduleReconcile(libraryIDs: [sourceID, destinationID])
        if sourceIsICloud && !destIsICloud {
            await OriginalsManager.shared.deleteCloudOriginals(picIDs: picIDs, in: sourceID)
        }

        if destIsICloud {
            await MainActor.run {
                SyncManager.shared.schedulePush(forLibrary: destinationID)
            }
            await OriginalsManager.shared.uploadMissingOriginals(in: destinationID)
        }
    }

    private struct Relocation {
        let filePath: String?
        let originalSynced: Bool
        let movedCloud: Bool
    }

    // swiftlint:disable:next function_parameter_count
    private func relocatePic(
        _ record: PicMoveRecord, sourceID: String, destinationID: String,
        sourceIsICloud: Bool, destIsICloud: Bool,
        sourceActor: DataActor, destActor: DataActor
    ) async -> Relocation? {
        let mediaType = record.resolvedMediaType
        if sourceIsICloud {
            if destIsICloud {
                let ok = await OriginalsManager.shared.moveCloudOriginal(
                    picID: record.id, mediaType: mediaType, from: sourceID, to: destinationID)
                return ok ? Relocation(filePath: nil, originalSynced: true, movedCloud: true) : nil
            }
            switch mediaType {
            case .pic:
                guard let data = await OriginalsManager.shared.fetchOriginal(picID: record.id, in: sourceID),
                      let path = await destActor.saveImageFile(data, id: record.id) else { return nil }
                return Relocation(filePath: path, originalSynced: false, movedCloud: false)
            case .video:
                guard let url = await OriginalsManager.shared.materializedVideoURL(picID: record.id, in: sourceID),
                      let data = try? Data(contentsOf: url) else { return nil }
                let ext = videoExtension(fromRelativePath: record.filePath, fallback: url)
                guard let path = await destActor.saveVideoFile(data, id: record.id, fileExtension: ext) else {
                    return nil
                }
                return Relocation(filePath: path, originalSynced: false, movedCloud: false)
            }
        } else {
            guard let sourcePath = record.filePath else { return nil }
            switch mediaType {
            case .pic:
                let sourceURL = sourceActor.imageFileURL(forRelativePath: sourcePath)
                guard let path = await destActor.adoptImageFile(from: sourceURL, id: record.id) else { return nil }
                return Relocation(filePath: path, originalSynced: false, movedCloud: false)
            case .video:
                let sourceURL = sourceActor.videoFileURL(forRelativePath: sourcePath)
                let ext = (sourcePath as NSString).pathExtension
                guard let path = await destActor.adoptVideoFile(
                    from: sourceURL, id: record.id, fileExtension: ext.isEmpty ? "mov" : ext) else { return nil }
                return Relocation(filePath: path, originalSynced: false, movedCloud: false)
            }
        }
    }

    private func postProgress(completed: Int, total: Int) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .libraryMoveProgress, object: nil,
                userInfo: ["completed": completed, "total": total])
        }
    }

    private func videoExtension(fromRelativePath path: String?, fallback url: URL) -> String {
        if let path {
            let ext = (path as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }
        let ext = url.pathExtension
        return ext.isEmpty ? "mov" : ext
    }
}
