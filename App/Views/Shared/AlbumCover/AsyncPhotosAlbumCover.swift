import Engine
import Photos
import SwiftUI

extension AlbumCover {

    /// Album cover (Photos library album)
    struct AsyncPhotosAlbumCover: View {

        var collection: PHAssetCollection
        var length: CGFloat?
        var refreshID: Int = 0

        @Environment(\.displayScale) private var displayScale

        @State private var primaryImage: Image?
        @State private var secondaryImage: Image?
        @State private var tertiaryImage: Image?
        @State private var picCount: Int = 0

        var body: some View {
            AlbumCover(name: collection.localizedTitle ?? "",
                       length: length,
                       picCount: picCount,
                       albumCount: 0,
                       primaryImage: primaryImage,
                       secondaryImage: secondaryImage,
                       tertiaryImage: tertiaryImage)
            .task(id: "\(collection.localIdentifier)-\(refreshID)") {
                loadRepresentativePhotos()
            }
        }

        private func loadRepresentativePhotos() {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(
                format: "mediaType = %d OR mediaType = %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let estimated = collection.estimatedAssetCount
            if estimated != NSNotFound {
                picCount = estimated
                fetchOptions.fetchLimit = 3
            }

            let result = PHAsset.fetchAssets(in: collection, options: fetchOptions)

            if estimated == NSNotFound {
                picCount = result.count
            }

            let manager = PHCachingImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            let coverLength = length ?? 200
            let targetSize = CGSize(width: coverLength * displayScale,
                                    height: coverLength * displayScale)

            result.enumerateObjects { asset, index, _ in
                manager.requestImage(for: asset, targetSize: targetSize,
                                     contentMode: .aspectFill, options: options) { uiImage, _ in
                    if let uiImage {
                        let image = Image(uiImage: uiImage)
                        DispatchQueue.main.async {
                            switch index {
                            case 0: self.primaryImage = image
                            case 1: self.secondaryImage = image
                            case 2: self.tertiaryImage = image
                            default: break
                            }
                        }
                    }
                }
            }
        }
    }

}
