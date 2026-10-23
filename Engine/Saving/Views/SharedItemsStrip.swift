import SwiftUI

public struct SharedItemsStrip: View {

    var items: [SharedItem]

    public init(items: [SharedItem]) {
        self.items = items
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8.0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Group {
                        if let data = item.imageData, let image = UIImage(data: data) {
                            let thumbnail = image.preparingThumbnail(of: CGSize(width: 240.0, height: 240.0)) ?? image
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: item.imageData == nil ? "video.fill" : "photo")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 72.0, height: 72.0)
                    .clipShape(.rect(cornerRadius: 10.0))
                }
            }
            .padding(.horizontal, 20.0)
        }
        .scrollIndicators(.hidden)
    }
}
