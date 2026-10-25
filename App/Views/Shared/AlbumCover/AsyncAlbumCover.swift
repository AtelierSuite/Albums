import Engine
import SwiftUI

extension AlbumCover {

    /// Album cover (local database)
    struct AsyncAlbumCover: View {

        var album: Album
        var length: CGFloat?
        var isDownloading: Bool = false
        var style: AlbumCoverStyle = .stack

        @State private var primaryImage: Image?
        @State private var secondaryImage: Image?
        @State private var tertiaryImage: Image?
        @State private var loadedCoverID: UUID?
        @State private var loadedToken: AlbumCoverCache.InvalidationToken?

        var body: some View {
            AlbumCover(name: album.name,
                       length: length,
                       picCount: album.picCount(),
                       albumCount: album.albumCount(),
                       primaryImage: primaryImage,
                       secondaryImage: secondaryImage,
                       tertiaryImage: tertiaryImage,
                       isDownloading: isDownloading,
                       style: style)
            .onChange(of: AlbumCoverCache.shared.version) {
                guard !loadFromCache(), let loadedToken,
                      loadedToken != AlbumCoverCache.shared.invalidationToken(forAlbumID: album.id) else { return }
                Task {
                    await AlbumCoverCache.shared.loadCover(for: album)
                }
            }
            .onChange(of: album.identifiableString()) {
                loadFromCache()
            }
            .onAppear {
                loadFromCache()
            }
        }

        @discardableResult
        private func loadFromCache() -> Bool {
            guard let cached = AlbumCoverCache.shared.images(forAlbumID: album.id) else { return false }
            guard cached.id != loadedCoverID else { return true }
            primaryImage = cached.primary
            secondaryImage = cached.secondary
            tertiaryImage = cached.tertiary
            loadedCoverID = cached.id
            loadedToken = AlbumCoverCache.shared.invalidationToken(forAlbumID: album.id)
            return true
        }
    }
}
