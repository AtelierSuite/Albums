import Combine
import Engine
import SwiftUI

struct AlbumLabelStyle {
    var cover: AlbumCoverStyle = .stack
    var titleFont: Font = .caption2.weight(.semibold)
    var countFont: Font?
    var compactCount = false
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 2.0

    init() {}

    init(viewStyle: AlbumViewStyle, coverWidth: CGFloat) {
        cover = viewStyle.coverStyle
        switch coverWidth {
        case 130...:
            titleFont = .subheadline.weight(.semibold)
            countFont = .footnote
        case 100...:
            titleFont = .footnote.weight(.semibold)
            countFont = .caption2
            compactCount = true
        case 64...:
            titleFont = .caption.weight(.semibold)
            countFont = .caption2
            compactCount = true
        default:
            titleFont = .caption2.weight(.semibold)
            countFont = nil
        }
        switch cover {
        case .stack:
            countFont = nil
            spacing = viewStyle.isCarousel ? 6.0 : 2.0
        case .flat, .peek:
            alignment = .leading
            spacing = 5.0
        case .mosaic:
            spacing = 5.0
        }
    }
}

struct AlbumCountText: View {

    var picCount: Int
    var albumCount: Int
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 6.0) {
                HStack(spacing: 2.0) {
                    Image(systemName: "photo")
                    Text(picCount, format: .number)
                }
                if albumCount > 0 {
                    HStack(spacing: 2.0) {
                        Image(systemName: "rectangle.stack")
                        Text(albumCount, format: .number)
                    }
                }
            }
            .imageScale(.small)
        } else if albumCount == 0 {
            Text("Albums.PicCount.\(picCount)", tableName: "Albums")
        } else {
            Text("Albums.Detail.\(picCount),\(albumCount)", tableName: "Albums")
        }
    }
}

struct AlbumGridLabel: View {

    var namespace: Namespace.ID?
    var album: Album
    var length: CGFloat?
    var style = AlbumLabelStyle()

    @State private var downloadFraction: Double?

    private var progressPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: Notification.Name("OfflineAlbumDownloadProgress"))
    }

    var body: some View {
        AlbumGridLabelLayout(namespace: namespace, id: album.id, title: album.name,
                             picCount: album.picCount(), albumCount: album.albumCount(),
                             length: length, style: style) {
            AlbumCover.AsyncAlbumCover(album: album, length: length,
                                      isDownloading: downloadFraction != nil,
                                      style: style.cover)
            .overlay {
                if let progress = downloadFraction {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.35), lineWidth: 5.0)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 5.0, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 36.0, height: 36.0)
                    .shadow(color: .black.opacity(0.3), radius: 2.0)
                    .animation(.smooth, value: progress)
                }
            }
        }
        .onReceive(progressPublisher) { note in
            guard note.userInfo?["albumID"] as? String == album.id else { return }
            downloadFraction = note.userInfo?["fraction"] as? Double
        }
    }
}

struct AlbumChipLabel: View {

    var namespace: Namespace.ID
    var album: Album

    var body: some View {
        AlbumChipLabelLayout(namespace: namespace, id: album.id, title: album.name,
                             picCount: album.picCount(), albumCount: album.albumCount()) {
            AlbumCover.AsyncAlbumCover(album: album, length: 40.0, style: .flat(cornerRadius: 9.0))
        }
    }
}
