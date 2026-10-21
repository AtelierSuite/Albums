import Engine
import Photos
import SwiftUI

extension PhotosFolderImportPickerView {

    func startFolderImport(_ folder: PHCollectionList) {
        isImporting = true
        let parentAlbumID = selectedAlbum?.id
        Task {
            var job = ImportJob(
                libraryID: DataActor.shared.collectionID,
                destinationAlbumID: parentAlbumID,
                destinationAlbumName: selectedAlbum?.name
            )
            let folderName = folder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import")
            let rootAlbum = await DataActor.shared.createAlbum(folderName, parentAlbumID: parentAlbumID)
            job.createdAlbumIDs.append(rootAlbum.id)
            await planFolderImport(folder, parentAlbumID: rootAlbum.id, into: &job)

            let result = await ImportManager.shared.run(job)
            if result.wasCancelled {
                onDismiss()
                return
            }
            importCompletedCount = result.importedCount
            doWithAnimation {
                isImportCompleted = true
            }
        }
    }

    private func planFolderImport(
        _ folder: PHCollectionList, parentAlbumID: String, into job: inout ImportJob
    ) async {
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
            job.createdAlbumIDs.append(childAlbum.id)
            job.items.append(contentsOf: importItems(in: album, albumID: childAlbum.id))
        }

        for subfolder in subfolders {
            let subfolderName = subfolder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import")
            let childAlbum = await DataActor.shared.createAlbum(subfolderName, parentAlbumID: parentAlbumID)
            job.createdAlbumIDs.append(childAlbum.id)
            await planFolderImport(subfolder, parentAlbumID: childAlbum.id, into: &job)
        }
    }

    private func importItems(in collection: PHAssetCollection, albumID: String) -> [ImportItem] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var items: [ImportItem] = []
        PHAsset.fetchAssets(in: collection, options: fetchOptions).enumerateObjects { asset, _, _ in
            items.append(ImportItem(
                source: .photosAsset(localIdentifier: asset.localIdentifier, isVideo: asset.mediaType == .video),
                albumID: albumID
            ))
        }
        return items
    }
}
