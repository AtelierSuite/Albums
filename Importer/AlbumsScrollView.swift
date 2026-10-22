import Engine
import SwiftUI

struct AlbumsScrollView: View {

    var title: LocalizedStringKey
    var session: SaveSession
    var parentAlbum: Album?
    @Binding var isSearching: Bool
    var focusSearchOnAppear: Bool = false
    @State var albums: [Album] = []
    @State var searchResults: [Album]?
    @State var isAlbumsLoaded: Bool = false
    @State var searchText: String = ""
    @State var isSearchPresented: Bool = false

    @AppStorage(wrappedValue: AlbumViewStyle.mosaicGrid, "AlbumViewStyle",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var style: AlbumViewStyle
    @AppStorage(wrappedValue: SortType.nameAscending, "AlbumSort",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var albumSort: SortType

    var displayedAlbums: [Album] {
        searchResults ?? albums
    }

    var body: some View {
        ScrollView(.vertical) {
            if isAlbumsLoaded {
                if displayedAlbums.isEmpty {
                    if searchResults != nil && !searchText.isEmpty {
                        Text("Albums.NoSearchResults", tableName: "Albums")
                            .foregroundStyle(.secondary)
                            .padding(20.0)
                    } else {
                        Text("Albums.NoMoreAlbums", tableName: "Albums")
                            .foregroundStyle(.secondary)
                            .padding(20.0)
                    }
                } else {
                    AlbumsSection(albums: displayedAlbums, style: style,
                                  enablesContextMenu: false) { _ in
                    }
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(20.0)
            }
        }
        .navigationTitle(title)
        .onAppear {
            if focusSearchOnAppear {
                isSearchPresented = true
            }
            Task {
                do {
                    let albums = try await DataActor.shared.albumsWithCounts(
                        in: parentAlbum, sortedBy: albumSort
                    )
                    await MainActor.run {
                        self.albums = albums
                        isAlbumsLoaded = true
                    }
                    await AlbumCoverCache.shared.loadCovers(for: albums)
                } catch {
                    debugPrint(error.localizedDescription)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            isSearching = !newValue.isEmpty
            if newValue.isEmpty {
                searchResults = nil
            } else {
                Task {
                    do {
                        let results = try await DataActor.shared.searchAlbums(
                            matching: newValue, in: parentAlbum, sortedBy: albumSort
                        )
                        await MainActor.run {
                            searchResults = results
                        }
                    } catch {
                        debugPrint(error.localizedDescription)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) {
                    session.cancel()
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Albums.Search.Prompt", tableName: "Albums"))
    }
}
