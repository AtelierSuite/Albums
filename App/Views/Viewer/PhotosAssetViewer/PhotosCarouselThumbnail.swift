import Engine
import Photos
import SwiftUI

struct PhotosCarouselThumbnail: View {

    let asset: PHAsset
    let isSelected: Bool

    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: PlatformImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .frame(width: 48.0, height: 48.0)
            .overlay {
                if let thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: 4.0))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4.0)
                        .stroke(.accent, lineWidth: 2.0)
                }
            }
            .opacity(isSelected ? 1.0 : 0.6)
            .task(id: asset.localIdentifier) {
                loadThumbnail()
            }
            .onDisappear {
                if let requestID {
                    PHCachingImageManager.default().cancelImageRequest(requestID)
                    self.requestID = nil
                }
                thumbnail = nil
            }
    }

    private func loadThumbnail() {
        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: 48.0 * displayScale,
                                height: 48.0 * displayScale)

        requestID = manager.requestImage(for: asset, targetSize: targetSize,
                             contentMode: .aspectFill, options: options) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    self.thumbnail = result
                }
            }
        }
    }
}
