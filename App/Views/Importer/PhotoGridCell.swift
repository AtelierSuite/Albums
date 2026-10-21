import Engine
import Photos
import SwiftUI

struct PhotoGridCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                PhotoThumbnailView(asset: asset, size: CGSize(width: 100, height: 100))
                    .frame(minWidth: 80, minHeight: 80)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                if asset.mediaType == .video {
                    Text(formatDuration(asset.duration))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                SelectionOverlay(isSelected)
            }
            .clipShape(.rect(cornerRadius: 4.0))
        }
        .buttonStyle(.plain)
    }
}
