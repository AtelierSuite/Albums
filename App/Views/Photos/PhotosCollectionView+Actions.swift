import Photos
import SwiftUI

// MARK: - Actions

extension PhotosCollectionView {
    func confirmDeletePhotosAlbum() {
        guard let album = albumToDelete else { return }
        Task {
            do {
                try await photosManager.deleteAlbum(album)
                await MainActor.run {
                    albumToDelete = nil
                    refreshCollections()
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }

    func confirmDeletePhotosFolder() {
        guard let folder = folderToDelete else { return }
        Task {
            do {
                try await photosManager.deleteFolder(folder)
                await MainActor.run {
                    folderToDelete = nil
                    refreshCollections()
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }

    func oriented(_ assets: [PHAsset]) -> [PHAsset] {
        picSort.isAscending ? assets.reversed() : assets
    }

    func refreshCollections() {
        items = photosManager.fetchTopLevelCollections().sortedAlbums(by: albumSort)
    }

    func addDroppedAsset(_ transferable: PHAssetTransferable, to collection: PHAssetCollection) {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [transferable.localIdentifier], options: nil)
        guard let asset = results.firstObject else { return }
        Task {
            do {
                try await photosManager.addAssets([asset], to: collection)
                let updatedAssets = oriented(await photosManager.fetchAssetsNotInAnyAlbum())
                await MainActor.run {
                    withAnimation(.smooth.speed(2.0)) {
                        rootAssets = updatedAssets
                        refreshCollections()
                        coverRefreshID += 1
                    }
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
