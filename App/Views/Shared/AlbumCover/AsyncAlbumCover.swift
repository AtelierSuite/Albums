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
        @State private var isLoaded = false

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
                if AlbumCoverCache.shared.images(forAlbumID: album.id) == nil {
                    guard isLoaded else { return }
                    isLoaded = false
                    primaryImage = nil
                    secondaryImage = nil
                    tertiaryImage = nil
                    // Reload this single cover (e.g. after eviction or invalidation)
                    Task {
                        await AlbumCoverCache.shared.loadCover(for: album)
                    }
                } else {
                    loadFromCache()
                }
            }
            .onChange(of: album.identifiableString()) {
                isLoaded = false
                loadFromCache()
            }
            .onAppear {
                loadFromCache()
            }
        }

        @discardableResult
        private func loadFromCache() -> Bool {
            guard !isLoaded else { return true }
            if let cached = AlbumCoverCache.shared.images(forAlbumID: album.id) {
                primaryImage = cached.primary
                secondaryImage = cached.secondary
                tertiaryImage = cached.tertiary
                isLoaded = true
                return true
            }
            return false
        }
    }
}
