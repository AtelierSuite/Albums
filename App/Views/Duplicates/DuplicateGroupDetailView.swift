import Engine
import SwiftUI

struct DuplicateDetailCard: View {

    let pic: Pic
    var dataActor: DataActor
    let isSelectedForDeletion: Bool
    let isKept: Bool
    let onToggle: () -> Void

    @State private var imageSize: String?
    @State private var fileSize: String?

    var body: some View {
        Button { onToggle() } label: {
            VStack(spacing: 6.0) {
                PicLabel(pic: pic, showsPinBadge: pic.isPinned)
                    .frame(width: 120.0, height: 120.0)
                    .clipShape(.rect(cornerRadius: 10.0))
                    .overlay(alignment: .bottomTrailing) {
                        SelectionOverlay(isSelectedForDeletion)
                    }
                    .overlay(alignment: .topLeading) {
                        if isKept {
                            DuplicateKeepBadge()
                        }
                    }

                VStack(spacing: 2.0) {
                    Text(pic.name)
                        .font(.caption)
                        .lineLimit(1)
                    if let imageSize {
                        Text(imageSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let fileSize {
                        Text(fileSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(pic.dateAdded, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120.0)
        }
        .buttonStyle(.plain)
        .task {
            if let data = await dataActor.imageData(forPicWithID: pic.id) {
                let byteCount = data.count
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB]
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: Int64(byteCount))

                if let image = UIImage(data: data) {
                    let pixelWidth = Int(image.size.width * image.scale)
                    let pixelHeight = Int(image.size.height * image.scale)
                    imageSize = "\(pixelWidth) × \(pixelHeight)"
                }
            }
        }
    }
}
