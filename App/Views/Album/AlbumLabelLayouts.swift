import SwiftUI

struct AlbumGridLabelLayout<Cover: View>: View {

    var namespace: Namespace.ID?
    var id: String
    var title: String
    var picCount: Int
    var albumCount: Int
    var length: CGFloat?
    var style = AlbumLabelStyle()
    @ViewBuilder var cover: () -> Cover

    var body: some View {
        VStack(alignment: style.alignment, spacing: style.spacing) {
            cover()
                .optionalMatchedGeometryEffect(id: "\(id).Image", in: namespace)
            VStack(alignment: style.alignment, spacing: 0.0) {
                Text(title)
                    .optionalMatchedGeometryEffect(id: "\(id).Title", in: namespace)
                    .font(style.titleFont)
                    .foregroundStyle(.primary)
                    .truncationMode(.middle)
                if let countFont = style.countFont {
                    AlbumCountText(picCount: picCount, albumCount: albumCount,
                                   compact: style.compactCount)
                        .font(countFont)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: length == nil ? .infinity : nil,
                   alignment: Alignment(horizontal: style.alignment, vertical: .center))
            .padding(.horizontal, 1.0)
            .padding(.bottom, 1.0)
        }
        .contentShape(.rect)
        .frame(width: length)
    }
}

struct AlbumChipLabelLayout<Cover: View>: View {

    var namespace: Namespace.ID?
    var id: String
    var title: String
    var picCount: Int
    var albumCount: Int
    @ViewBuilder var cover: () -> Cover

    var body: some View {
        HStack(alignment: .center, spacing: 8.0) {
            cover()
                .optionalMatchedGeometryEffect(id: "\(id).Image", in: namespace)
            VStack(alignment: .leading, spacing: 0.0) {
                Text(title)
                    .optionalMatchedGeometryEffect(id: "\(id).Title", in: namespace)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                AlbumCountText(picCount: picCount, albumCount: albumCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(.leading, 6.0)
        .padding(.trailing, 14.0)
        .padding(.vertical, 6.0)
        .background(Color(uiColor: .secondarySystemFill), in: .rect(cornerRadius: 14.0, style: .continuous))
        .contentShape(.rect(cornerRadius: 14.0))
    }
}

struct AlbumListRowLayout<Cover: View, Detail: View>: View {

    var namespace: Namespace.ID?
    var id: String
    var title: String
    @ViewBuilder var cover: () -> Cover
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            cover()
                .optionalMatchedGeometryEffect(id: "\(id).Image", in: namespace)
            VStack(alignment: .leading, spacing: 2.0) {
                Text(title)
                    .optionalMatchedGeometryEffect(id: "\(id).Title", in: namespace)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                detail()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .resizable()
                .scaledToFit()
                .frame(width: 11.0, height: 11.0)
                .foregroundStyle(.primary.opacity(0.25))
                .fontWeight(.bold)
        }
        .contentShape(.rect)
        .padding([.leading, .trailing], 20.0)
        .padding([.top, .bottom], 8.0)
    }
}
