import SwiftUI

struct RecentlyDeletedAlbumGridLabel: View {

    var length: CGFloat?
    var style = AlbumLabelStyle()

    var body: some View {
        VStack(alignment: style.alignment, spacing: style.spacing) {
            cover
            VStack(alignment: style.alignment, spacing: 0.0) {
                Text("RecentlyDeleted.Title", tableName: "Albums")
                    .font(style.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let countFont = style.countFont {
                    Text(verbatim: " ")
                        .font(countFont)
                }
            }
            .frame(maxWidth: length == nil ? .infinity : nil,
                   alignment: Alignment(horizontal: style.alignment, vertical: .center))
            .padding(.horizontal, 1.0)
            .padding(.bottom, 1.0)
        }
        .contentShape(.rect)
        .frame(width: length)
    }

    @ViewBuilder
    var cover: some View {
        switch style.cover {
        case .stack:
            RecentlyDeletedAlbumCover(length: length)
        case .flat(let cornerRadius):
            RecentlyDeletedFlatCover(length: length, cornerRadius: cornerRadius)
        case .peek:
            RecentlyDeletedFlatCover(length: length)
                .padding(.top, AlbumPeekCover.peekHeight)
        case .mosaic:
            RecentlyDeletedFlatCover(length: length, cornerRadius: 12.0)
        }
    }
}

struct RecentlyDeletedFlatCover: View {

    var length: CGFloat?
    var cornerRadius: CGFloat = 10.0

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(1.0, contentMode: .fit)
            .frame(width: length)
            .overlay {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct RecentlyDeletedAlbumChipLabel: View {

    var count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 8.0) {
            RecentlyDeletedFlatCover(length: 40.0, cornerRadius: 9.0)
            VStack(alignment: .leading, spacing: 0.0) {
                Text("RecentlyDeleted.Title", tableName: "Albums")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("RecentlyDeleted.Count.\(count)", tableName: "Albums")
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

struct RecentlyDeletedAlbumListRow: View {

    var count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            RecentlyDeletedAlbumCover(length: 48.0)
            VStack(alignment: .leading, spacing: 2.0) {
                Text("RecentlyDeleted.Title", tableName: "Albums")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("RecentlyDeleted.Count.\(count)", tableName: "Albums")
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

struct RecentlyDeletedAlbumCover: View {

    var length: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.92 / 1.16
            RoundedRectangle(cornerRadius: side * 0.12 / 0.92, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "trash")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.32, height: side * 0.32)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: length.map { $0 * 1.16 }, height: length.map { $0 * 1.16 })
        .padding(length.map { $0 * -0.08 } ?? 0)
    }
}
