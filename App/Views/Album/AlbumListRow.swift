import Engine
import SwiftUI

struct AlbumListRow: View {

    var namespace: Namespace.ID

    var album: Album

    var body: some View {
        AlbumListRowLayout(namespace: namespace, id: album.id, title: album.name) {
            AlbumCover.AsyncAlbumCover(album: album, length: 48.0)
        } detail: {
            Text("Albums.Detail.\(album.picCount()),\(album.albumCount())", tableName: "Albums")
        }
    }
}
