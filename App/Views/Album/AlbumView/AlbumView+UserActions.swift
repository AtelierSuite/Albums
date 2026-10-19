import Engine
import SwiftUI

extension AlbumView {

    func presentFileImporter() {
        #if targetEnvironment(macCatalyst)
        isFileImportSheetPresented = true
        #else
        isFileImporterPresented = true
        #endif
    }

    func deleteAlbum(_ album: Album) {
        isConfirmingDeleteAlbum = true
        albumPendingDeletion = album
    }

    func confirmDeleteAlbum(deletingContents: Bool) {
        if let albumPendingDeletion {
            Task {
                if deletingContents {
                    let deletedPicIDs = await DataActor.shared.deleteAlbumAndContents(
                        withID: albumPendingDeletion.id
                    )
                    await PColorActor.shared.deleteColors(forPicIDs: deletedPicIDs)
                    AlbumCoverCache.shared.removeImages(forAlbumID: albumPendingDeletion.id)
                    viewer.removePics(withIDs: Set(deletedPicIDs))
                    let collectionID = DataActor.shared.collectionID
                    Task.detached {
                        await OriginalsManager.shared.deleteCloudOriginals(
                            picIDs: deletedPicIDs, in: collectionID
                        )
                    }
                } else {
                    await DataActor.shared.deleteAlbum(withID: albumPendingDeletion.id)
                }
                await refreshData()
            }
        }
    }

    func deletePic(_ pic: Pic?) {
        if let pic {
            isConfirmingDeletePic = true
            picPendingDeletion = pic
        } else {
            isConfirmingDeleteSelectedPics = true
        }
    }

    func deletePics() {
        isConfirmingDeleteSelectedPics = true
    }

    func confirmDeletePic() {
        Task { [isSelectingPics, selectedPics] in
            var deletedIDs = Set<String>()
            if isSelectingPics {
                let picIDs = selectedPics.map(\.id)
                deletedIDs = Set(picIDs)
                await DataActor.shared.deletePics(withIDs: picIDs)
                await PColorActor.shared.deleteColors(forPicIDs: picIDs)
            } else {
                if let picPendingDeletion = picPendingDeletion {
                    await DataActor.shared.deletePic(withID: picPendingDeletion.id)
                    await PColorActor.shared.deleteColor(forPicWithID: picPendingDeletion.id)
                    deletedIDs.insert(picPendingDeletion.id)
                }
            }
            if let currentAlbum {
                AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
            }
            viewer.removePics(withIDs: deletedIDs)
            let collectionID = DataActor.shared.collectionID
            let idsForCleanup = Array(deletedIDs)
            Task.detached {
                await OriginalsManager.shared.deleteCloudOriginals(picIDs: idsForCleanup, in: collectionID)
            }
            self.selectedPics.removeAll()
            refreshPicsAndSet()
        }
    }

    func selectOrDeselectAllPics() {
        if pics.count == selectedPics.count {
            selectedPics.removeAll()
        } else {
            selectedPics.removeAll()
            selectedPics.append(contentsOf: pics)
        }
    }

    @MainActor
    func startOrStopSelectingPics() {
        doWithAnimation {
            if isSelectingPics {
                selectedPics.removeAll()
            }
            isSelectingPics.toggle()
        }
    }

    @discardableResult
    func importDrops(_ items: [Drop]) -> Bool {
        let fileURLs = items.compactMap(\.file)
        if !fileURLs.isEmpty {
            importFiles(fileURLs)
            return true
        }
        let images = items.compactMap(\.importedPhoto)
        if !images.isEmpty {
            importDroppedImages(images)
            return true
        }
        return false
    }

    func moveDropToAlbum(_ drops: [Drop], to album: Album) {
        let fromAlbumID = currentAlbum?.id
        Task {
            var movedPicIDs: [String] = []
            for drop in drops {
                if let transferable = drop.pic {
                    await movePicToAlbum(transferable.id, to: album)
                    movedPicIDs.append(transferable.id)
                } else if let transferable = drop.album {
                    if transferable.id != album.id {
                        await moveAlbumToAlbum(transferable.id, to: album)
                    }
                } else if let transferable = drop.importedPhoto {
                    await importPhotoToAlbum(transferable, to: album)
                }
            }
            await refreshData()
            if !movedPicIDs.isEmpty {
                MovedToast.showMoved(picIDs: movedPicIDs, to: album,
                                     from: fromAlbumID, using: DataActor.shared)
            }
        }
    }

    func movePicToAlbum(_ picID: String, to album: Album) async {
        await DataActor.shared.addPic(withID: picID, toAlbumWithID: album.id)
        if let currentAlbum {
            AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
        }
        AlbumCoverCache.shared.removeImages(forAlbumID: album.id)
    }

    func moveAlbumToAlbum(_ albumID: String, to album: Album) async {
        await DataActor.shared.addAlbum(withID: albumID, toAlbumWithID: album.id)
    }

    func importPhotoToAlbum(_ photo: Image, to album: Album) async {
        let uiImage = photo.render()
        if let data = uiImage?.data() {
            await DataActor.shared.createPic(Pic.newFilename(), data: data,
                                             inAlbumWithID: album.id)
        }
    }

    func refreshDataAfterPicMoved() {
        selectedPics.removeAll()
        Task {
            await refreshData()
        }
    }

    func selectOrDeselectPic(_ pic: Pic) {
        if isSelectingPics {
            if selectedPics.contains(where: { $0.id == pic.id }) {
                selectedPics.removeAll(where: { $0.id == pic.id })
            } else {
                selectedPics.append(pic)
            }
        } else {
            let picCopy = pic
            if UIDevice.current.userInterfaceIdiom == .phone {
                viewer.setDisplay(picCopy, in: pics) { [navigation] in
                    navigation.push(.picViewer(namespace: namespace), for: .collection)
                }
            } else {
#if targetEnvironment(macCatalyst)
                if openPicsInNewWindow {
                    openWindow(value: ViewerWindowValue.pic(
                        selectedID: picCopy.id, siblingIDs: pics.map(\.id)))
                } else {
                    viewer.setDisplay(picCopy, in: pics) { }
                }
#else
                viewer.setDisplay(picCopy, in: pics) { }
#endif
            }
        }
    }
}
