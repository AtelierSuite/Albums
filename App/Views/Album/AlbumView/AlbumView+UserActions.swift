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
                    let deletedPicIDs = await DataActor.shared.moveAlbumAndContentsToRecentlyDeleted(
                        withID: albumPendingDeletion.id
                    )
                    AlbumCoverCache.shared.removeImages(forAlbumID: albumPendingDeletion.id)
                    viewer.removePics(withIDs: Set(deletedPicIDs))
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
                deletedIDs = Set(selectedPics.map(\.id))
            } else if let picPendingDeletion {
                deletedIDs.insert(picPendingDeletion.id)
            }
            await DataActor.shared.moveToRecentlyDeleted(picIDs: Array(deletedIDs))
            if let currentAlbum {
                AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
            }
            viewer.removePics(withIDs: deletedIDs)
            await refreshRecentlyDeletedCount()
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

    func togglePin(for pics: [Pic]) {
        guard !pics.isEmpty else { return }
        let isPinning = pics.contains { !$0.isPinned }
        let picIDs = pics.map(\.id)
        Task {
            await DataActor.shared.setPinned(isPinning, forPicsWithIDs: picIDs)
            selectedPics.removeAll()
            refreshPicsAndSet()
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
            openPic(pic, in: pics)
        }
    }

    func openPic(_ pic: Pic, in pics: [Pic]) {
        let picCopy = pic
        if UIDevice.current.userInterfaceIdiom == .phone {
            viewer.setDisplay(picCopy, in: pics, origin: .album(id: currentAlbum?.id)) { [navigation] in
                navigation.push(.picViewer(namespace: namespace), for: .collection)
            }
        } else {
#if targetEnvironment(macCatalyst)
            if openPicsInNewWindow {
                openWindow(value: ViewerWindowValue.pic(
                    selectedID: picCopy.id, siblingIDs: pics.map(\.id)))
            } else {
                viewer.setDisplay(picCopy, in: pics, origin: .album(id: currentAlbum?.id)) { }
            }
#else
            viewer.setDisplay(picCopy, in: pics, origin: .album(id: currentAlbum?.id)) { }
#endif
        }
    }
}
