import Combine
import Engine
import SwiftUI

struct AlbumGridLabel: View {

    var namespace: Namespace.ID?
    var album: Album
    var length: CGFloat?

    @State private var downloadFraction: Double?

    private var progressPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: Notification.Name("OfflineAlbumDownloadProgress"))
    }

    var body: some View {
        VStack(alignment: .center, spacing: length == nil ? 2.0 : 6.0) {
            AlbumCover.AsyncAlbumCover(album: album, length: length,
                                      isDownloading: downloadFraction != nil)
            .optionalMatchedGeometryEffect(id: "\(album.id).Image", in: namespace)
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
            Text(album.name)
                .optionalMatchedGeometryEffect(id: "\(album.id).Title", in: namespace)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 1.0)
                .padding(.bottom, 1.0)
        }
        .contentShape(.rect)
        .frame(width: length)
        .onReceive(progressPublisher) { note in
            guard note.userInfo?["albumID"] as? String == album.id else { return }
            downloadFraction = note.userInfo?["fraction"] as? Double
        }
    }
}
