import Engine
import Photos
import SwiftUI

// MARK: - Actions

extension PhotosFolderView {
    func fetchContent() {
        if isNestedAlbumsEnabled {
            let resolved = photosManager.resolveNestedAlbums(in: folder)

            var collected: [PHCollectionItem] = []
            for album in resolved.albums {
                collected.append(.album(album))
            }
            for subfolder in resolved.folders {
                collected.append(.folder(subfolder))
            }
            items = collected

            if let ownPicsCollection = resolved.ownPicsCollection {
                ownPicsFetchResult = photosManager.fetchAssets(in: ownPicsCollection)
            }
        } else {
            items = photosManager.fetchCollections(in: folder)
        }
        hasFetched = true
    }

    func confirmDeletePhotosAlbum() {
        guard let album = albumToDelete else { return }
        Task {
            do {
                try await photosManager.deleteAlbum(album)
                await MainActor.run {
                    albumToDelete = nil
                    hasFetched = false
                    fetchContent()
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
                    hasFetched = false
                    fetchContent()
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }

    func addDroppedAsset(_ transferable: PHAssetTransferable, to collection: PHAssetCollection) {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [transferable.localIdentifier], options: nil)
        guard let asset = results.firstObject else { return }
        Task {
            do {
                try await photosManager.addAssets([asset], to: collection)
                await MainActor.run {
                    withAnimation(.smooth.speed(2.0)) {
                        fetchContent()
                        coverRefreshID += 1
                    }
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
