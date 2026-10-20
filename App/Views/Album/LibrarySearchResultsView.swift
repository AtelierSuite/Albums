import Engine
import SwiftUI

struct LibrarySearchResultsView: View {

    var namespace: Namespace.ID
    var results: LibrarySearchResults?
    var libraryName: String
    var onOpenPic: (Pic, [Pic]) -> Void

    var body: some View {
        if let results {
            if results.isEmpty {
                Text("Albums.Search.Library.NoResults", tableName: "Albums")
                    .foregroundStyle(.secondary)
                    .padding(20.0)
            } else {
                LazyVStack(alignment: .leading, spacing: 0.0) {
                    if !results.albums.isEmpty {
                        header(String(localized: "Albums.Albums", table: "Albums"),
                               count: results.albums.count)
                        ForEach(results.albums) { album in
                            NavigationLink(value: ViewPath.album(album: album)) {
                                row(title: album.name,
                                    subtitle: location(for: album.parentAlbumID, in: results)) {
                                    AlbumCover.AsyncAlbumCover(album: album, length: 48.0)
                                        .task {
                                            await AlbumCoverCache.shared.loadCover(for: album)
                                        }
                                }
                            }
                            .buttonStyleAdaptive()
                        }
                    }
                    if !results.pics.isEmpty {
                        header(String(localized: "Albums.Pics", table: "Albums"),
                               count: results.pics.count)
                            .padding(.top, results.albums.isEmpty ? 0.0 : 20.0)
                        ForEach(results.pics) { pic in
                            Button {
                                onOpenPic(pic, results.pics)
                            } label: {
                                row(title: pic.name,
                                    subtitle: location(for: pic.containingAlbumID, in: results)) {
                                    PicLabel(pic: pic)
                                        .frame(width: 48.0, height: 48.0)
                                        .matchedTransitionSource(id: pic.id, in: namespace)
                                }
                            }
                            .buttonStyleAdaptive()
                            .accessibilityIdentifier("pic:\(pic.name)")
                        }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(20.0)
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        SectionHeader(title: title, count: count)
            .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
    }

    private func location(for albumID: String?, in results: LibrarySearchResults) -> String {
        albumID.flatMap { results.albumNames[$0] } ?? libraryName
    }

    private func row<Thumbnail: View>(
        title: String, subtitle: String, @ViewBuilder thumbnail: () -> Thumbnail
    ) -> some View {
        HStack(alignment: .center, spacing: 16.0) {
            thumbnail()
            VStack(alignment: .leading, spacing: 2.0) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
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
