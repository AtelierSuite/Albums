import SwiftUI

struct RecentlyDeletedAlbumGridLabel: View {

    var length: CGFloat?

    var body: some View {
        VStack(alignment: .center, spacing: length == nil ? 2.0 : 6.0) {
            RecentlyDeletedAlbumCover(length: length)
            Text("RecentlyDeleted.Title", tableName: "Albums")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 1.0)
                .padding(.bottom, 1.0)
        }
        .contentShape(.rect)
        .frame(width: length)
    }
}

struct RecentlyDeletedAlbumListRow: View {

    var count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            RecentlyDeletedAlbumCover(length: 48.0)
            VStack(alignment: .leading, spacing: 2.0) {
                Text("RecentlyDeleted.Title", tableName: "Albums")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("RecentlyDeleted.Count.\(count)", tableName: "Albums")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: length.map { $0 * 1.16 }, height: length.map { $0 * 1.16 })
        .padding(length.map { $0 * -0.08 } ?? 0)
    }
}
