import Engine
import SwiftUI

struct AlbumListRow: View {

    @Environment(\.colorScheme) var colorScheme

    var namespace: Namespace.ID

    var album: Album

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            AlbumCover.AsyncAlbumCover(album: album, length: 48.0)
                .matchedGeometryEffect(id: "\(album.id).Image", in: namespace)
            VStack(alignment: .leading, spacing: 2.0) {
                Text(album.name)
                    .matchedGeometryEffect(id: "\(album.id).Title", in: namespace)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Albums.Detail.\(album.picCount()),\(album.albumCount())", tableName: "Albums")
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
