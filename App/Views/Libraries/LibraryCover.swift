import SwiftUI

struct LibraryCover: View {

    var images: [UIImage]
    var placeholderSystemImage: String
    var length: CGFloat

    private let spacing: CGFloat = 1.0

    var body: some View {
        Group {
            switch images.count {
            case 0:
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: length * 0.4))
                    .foregroundStyle(.accent)
                    .frame(width: length, height: length)
                    .background(.accent.opacity(0.15))
            case 1:
                tile(images[0], width: length, height: length)
            case 2:
                HStack(spacing: spacing) {
                    tile(images[0], width: half, height: length)
                    tile(images[1], width: half, height: length)
                }
            case 3:
                HStack(spacing: spacing) {
                    tile(images[0], width: half, height: length)
                    VStack(spacing: spacing) {
                        tile(images[1], width: half, height: half)
                        tile(images[2], width: half, height: half)
                    }
                }
            default:
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        tile(images[0], width: half, height: half)
                        tile(images[1], width: half, height: half)
                    }
                    HStack(spacing: spacing) {
                        tile(images[2], width: half, height: half)
                        tile(images[3], width: half, height: half)
                    }
                }
            }
        }
        .frame(width: length, height: length)
        .clipShape(.rect(cornerRadius: length * 0.22))
    }

    private var half: CGFloat {
        (length - spacing) / 2.0
    }

    private func tile(_ image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
    }
}
