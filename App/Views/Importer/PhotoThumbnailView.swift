import Engine
import Photos
import SwiftUI

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onDisappear {
            if let requestID {
                PHCachingImageManager.default().cancelImageRequest(requestID)
                self.requestID = nil
            }
        }
    }

    private func loadThumbnail() {
        guard image == nil else { return }
        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        let targetSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)

        requestID = manager.requestImage(for: asset, targetSize: targetSize,
                             contentMode: .aspectFill, options: options) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }
}
