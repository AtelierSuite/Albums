import Engine
import SwiftUI

struct LibraryAlbumPickerView: View {

    let libraryID: String
    let parentAlbum: Album?
    let onOpen: (Album) -> Void
    let onMoveHere: () -> Void

    @Namespace private var namespace
    @State private var albums: [Album] = []
    @State private var isLoaded: Bool = false

    private let columnCount = 3

    var body: some View {
        ScrollView(.vertical) {
            if isLoaded {
                if albums.isEmpty {
                    Text("Albums.NoMoreAlbums", tableName: "Albums")
                        .foregroundStyle(.secondary)
                        .padding(20.0)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10.0),
                                       count: columnCount),
                        spacing: 12.0
                    ) {
                        ForEach(albums) { album in
                            Button {
                                onOpen(album)
                            } label: {
                                AlbumGridLabel(namespace: namespace, album: album)
                            }
                            .buttonStyleAdaptive()
                            .id(album.identifiableString())
                        }
                    }
                    .padding(.horizontal, 14.0)
                    .padding(.top, 10.0)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(20.0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onMoveHere()
            } label: {
                Text("Move.MoveHere")
                    .bold()
            }
            .buttonStyle(.glassProminent)
            .tint(.accent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
            .padding(20.0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    func load() async {
        let loaded = (try? await DataActor.instance(for: libraryID)
            .albumsWithCounts(in: parentAlbum, sortedBy: .nameAscending)) ?? []
        await MainActor.run {
            albums = loaded
            isLoaded = true
        }
        await AlbumCoverCache.shared.loadCovers(for: loaded, inLibrary: libraryID)
    }
}
