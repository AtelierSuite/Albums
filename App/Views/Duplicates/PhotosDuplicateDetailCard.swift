import Engine
import Photos
import SwiftUI

struct PhotosDuplicateDetailCard: View {

    let asset: PHAsset
    let isSelectedForDeletion: Bool
    let onToggle: () -> Void

    @State private var thumbnail: UIImage?
    @State private var fileSize: String?

    var body: some View {
        Button { onToggle() } label: {
            VStack(spacing: 6.0) {
                ZStack {
                    Rectangle()
                        .fill(.primary.opacity(0.05))
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 120.0, height: 120.0)
                .clipShape(.rect(cornerRadius: 10.0))
                .overlay(alignment: .bottomTrailing) {
                    SelectionOverlay(isSelectedForDeletion)
                }

                VStack(spacing: 2.0) {
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let fileSize {
                        Text(fileSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let creationDate = asset.creationDate {
                        Text(creationDate, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120.0)
        }
        .buttonStyle(.plain)
        .task {
            loadThumbnail()
            loadFileSize()
        }
    }

    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        PHCachingImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 240, height: 240),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    self.thumbnail = result
                }
            }
        }
    }

    private func loadFileSize() {
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first,
           let sizeValue = resource.value(forKey: "fileSize") as? Int64, sizeValue > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            DispatchQueue.main.async {
                self.fileSize = formatter.string(fromByteCount: sizeValue)
            }
        }
    }
}
