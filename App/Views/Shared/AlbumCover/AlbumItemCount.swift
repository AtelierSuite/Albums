import Engine
import SwiftUI

struct AlbumItemCount: View {

    let picCount: Int
    let albumCount: Int
    var includesAlbums: Bool = true

    init(picCount: Int, albumCount: Int, includesAlbums: Bool = true) {
        self.picCount = picCount
        self.albumCount = albumCount
        self.includesAlbums = includesAlbums
    }

    init(of album: Album) {
        self.picCount = album.picCount()
        self.albumCount = album.albumCount()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6.0) {
            if picCount > 0 || albumCount > 0 {
                if picCount > 0 {
                    iconAndLabel(picCount, systemImage: "photo.fill")
                }
                if albumCount > 0 {
                    iconAndLabel(albumCount, systemImage: "rectangle.stack.fill")
                }
            } else {
                iconAndLabel(0, systemImage: "photo.fill")
                if includesAlbums {
                    iconAndLabel(0, systemImage: "rectangle.stack.fill")
                }
            }
        }
        .font(.system(size: 10.0, weight: .semibold, design: .rounded))
    }

    func iconAndLabel(_ count: Int, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 2.0) {
            Image(systemName: systemImage)
            Text(String(count))
        }
    }
}
