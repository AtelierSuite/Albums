import Engine
import SwiftUI
import UIKit

extension Notification.Name {
    static let picThumbnailDidChange = Notification.Name("PicThumbnailDidChange")
}

struct OrientationEditSession {
    let collectionID: String
    var baseDataTask: Task<Data?, Never>
    var written: PicOrientationEdit = .identity
    var writtenData: Data?
    var generation: Int = 0
    var lastEditAt: ContinuousClock.Instant = .now
    var isWriting: Bool = false
}

extension ViewerManager {

    static let orientationAnimation: Animation = .smooth(duration: 0.35)
    static let orientationSaveDelay: Duration = .milliseconds(450)

    var canEditDisplayedOrientation: Bool {
        guard let displayedPic, !displayedPic.isVideo else { return false }
        return isFullImageLoaded && displayedImage != nil
    }

    func orientationEdit(for picID: String) -> PicOrientationEdit {
        orientationEdits[picID] ?? .identity
    }

    func rotateDisplayedPic() {
        editDisplayedOrientation { $0.rotatedCounterClockwise() }
    }

    func flipDisplayedPic() {
        editDisplayedOrientation { $0.flippedHorizontally() }
    }

    private func editDisplayedOrientation(_ transform: (PicOrientationEdit) -> PicOrientationEdit) {
        guard canEditDisplayedOrientation else { return }
        let picID = displayedPicID
        let edited = transform(orientationEdit(for: picID))
        withAnimation(Self.orientationAnimation) {
            orientationEdits[picID] = edited
        }
        var session = orientationSessions[picID] ?? makeOrientationSession(for: picID)
        session.generation += 1
        session.lastEditAt = .now
        let startsWriter = !session.isWriting
        session.isWriting = true
        orientationSessions[picID] = session
        if startsWriter {
            Task { await runOrientationWriter(for: picID) }
        }
    }

    func discardOrientationEdits(forPicIDs picIDs: some Sequence<String>) {
        for picID in picIDs {
            orientationSessions[picID] = nil
            orientationEdits[picID] = nil
        }
    }

    private func makeOrientationSession(for picID: String) -> OrientationEditSession {
        let collectionID = DataActor.shared.collectionID
        let baseDataTask = Task<Data?, Never> {
            let dataActor = DataActor.instance(for: collectionID)
            if let data = await dataActor.imageData(forPicWithID: picID) {
                return data
            }
            return await OriginalsManager.shared.fetchOriginal(picID: picID, in: collectionID)
        }
        return OrientationEditSession(collectionID: collectionID, baseDataTask: baseDataTask)
    }

    private func runOrientationWriter(for picID: String) async {
        while let session = orientationSessions[picID] {
            let quietFor = ContinuousClock.now - session.lastEditAt
            if quietFor < Self.orientationSaveDelay {
                try? await Task.sleep(for: Self.orientationSaveDelay - quietFor)
                continue
            }
            let target = orientationEdit(for: picID).normalized
            if target != session.written {
                if let data = await writeOrientation(target, for: picID, in: session) {
                    orientationSessions[picID]?.written = target
                    orientationSessions[picID]?.writtenData = data
                } else if orientationSessions[picID] != nil {
                    revertOrientation(for: picID, to: session.written)
                }
                continue
            }
            let generation = session.generation
            var image: UIImage?
            if let data = session.writtenData {
                image = await UIImage(data: data)?.byPreparingForDisplay()
            }
            guard let current = orientationSessions[picID], current.generation == generation,
                  ContinuousClock.now - current.lastEditAt >= Self.orientationSaveDelay else { continue }
            finishOrientationSession(for: picID, image: image, didWrite: session.writtenData != nil)
            return
        }
    }

    private func writeOrientation(_ target: PicOrientationEdit, for picID: String,
                                  in session: OrientationEditSession) async -> Data? {
        guard let baseData = await session.baseDataTask.value else { return nil }
        let edited = await Task.detached(priority: .userInitiated) {
            PicOrientationEditor.apply(target, to: baseData)
        }.value
        guard let edited else { return nil }
        let collectionID = session.collectionID
        await ContentCredentialsScanner.shared.ensureScanned(
            picID: picID, imageData: baseData, in: DataActor.instance(for: collectionID)
        )
        let cloudOutcome = await OriginalsManager.shared.replaceCloudImageOriginal(
            picID: picID, with: edited, in: collectionID
        )
        guard cloudOutcome != .failed else { return nil }
        let dataActor = DataActor.instance(for: collectionID)
        guard let replacement = await dataActor.replaceImageOriginal(
            forPicWithID: picID, with: edited, isMirroredToCloud: cloudOutcome == .replaced
        ) else {
            if cloudOutcome == .replaced, await dataActor.pic(forID: picID) == nil {
                await OriginalsManager.shared.deleteCloudOriginal(picID: picID, in: collectionID)
            }
            return nil
        }
        await HashActor.instance(for: collectionID).deleteHash(forPicWithID: picID)
        await FeaturePrintActor.instance(for: collectionID).deletePrint(forPicWithID: picID)
        await updateThumbnail(replacement.thumbnailData, forPicWithID: picID)
        if let albumID = replacement.albumID, collectionID == DataActor.shared.collectionID {
            AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
        }
        return edited
    }

    private func updateThumbnail(_ thumbnailData: Data?, forPicWithID picID: String) async {
        for pic in allPics where pic.id == picID {
            pic.thumbnailData = thumbnailData
        }
        if displayedPic?.id == picID {
            displayedPic?.thumbnailData = thumbnailData
        }
        if let thumbnailData, let thumbnail = await UIImage(data: thumbnailData)?.byPreparingForDisplay() {
            ThumbnailCache.shared.setImage(thumbnail, forKey: picID)
        }
        NotificationCenter.default.post(name: .picThumbnailDidChange, object: picID)
    }

    private func revertOrientation(for picID: String, to written: PicOrientationEdit) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let current = orientationEdit(for: picID)
        var difference = (written.quarterTurns - current.normalized.quarterTurns) % 4
        if difference > 2 { difference -= 4 }
        if difference < -1 { difference += 4 }
        withAnimation(Self.orientationAnimation) {
            orientationEdits[picID] = PicOrientationEdit(quarterTurns: current.quarterTurns + difference,
                                                         isMirrored: written.isMirrored)
        }
        orientationSessions[picID]?.generation += 1
        orientationSessions[picID]?.lastEditAt = .now
    }

    private func finishOrientationSession(for picID: String, image: UIImage?, didWrite: Bool) {
        orientationSessions[picID] = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if didWrite {
                imageCache[picID] = image
                if displayedPicID == picID {
                    displayedThumbnail = ThumbnailCache.shared.image(forKey: picID) ?? displayedThumbnail
                    if let image {
                        displayedImage = image
                    } else {
                        displayedImage = nil
                        isFullImageLoaded = false
                    }
                }
            }
            orientationEdits[picID] = nil
        }
        if didWrite, image == nil, displayedPicID == picID {
            navigateTo(index: currentIndex)
        }
    }
}
