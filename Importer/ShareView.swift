import Engine
import SwiftUI

struct ShareView: View {

    var session: SaveSession

    @State var viewPath: [ViewPath] = []
    @State var isSearching: Bool = false
    @State var libraryName: String = ""

    @AppStorage(wrappedValue: false, "ShareSheetOpenSearch",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var openSearchWhenSharing: Bool
    @AppStorage(wrappedValue: false, "ShareSheetQuickImport",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var quickImport: Bool
    @AppStorage(wrappedValue: "", "ShareSheetDefaultAlbum",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var defaultAlbumID: String

    var hasDefaultAlbum: Bool {
        quickImport && !defaultAlbumID.isEmpty
    }

    var body: some View {
        ZStack {
            if session.items.isEmpty {
                NothingToSaveView(session: session)
            } else if !hasDefaultAlbum {
                VStack(spacing: 0.0) {
                    NavigationStack(path: $viewPath) {
                        AlbumsScrollView(title: "ViewTitle.Importer",
                                         isSearching: $isSearching,
                                         focusSearchOnAppear: openSearchWhenSharing)
                            .navigationDestination(for: ViewPath.self) { viewPath in
                                if case .album(let album) = viewPath {
                                    AlbumsScrollView(title: LocalizedStringKey(album.name),
                                                     parentAlbum: album,
                                                     isSearching: $isSearching)
                                } else {
                                    Color.clear
                                }
                            }
                    }
                    importButton
                }
            }
            SaveSessionOverlay(session: session)
        }
        .background(Color(uiColor: .systemBackground))
        .task {
            libraryName = await LibrariesActor.shared.library(for: DataActor.shared.collectionID)?.name ?? ""
            if hasDefaultAlbum, !session.items.isEmpty {
                let albumID = defaultAlbumID == "__collection__" ? nil : defaultAlbumID
                let album: Album? = if let albumID { await DataActor.shared.album(for: albumID) } else { nil }
                await save(to: album)
            }
        }
        .onChange(of: viewPath) { _, newPath in
            if quickImport, case .album(let album) = newPath.last, album.albumCount() == 0 {
                Task { await save(to: album) }
            }
        }
    }

    private var importButton: some View {
        VStack(alignment: .center, spacing: 16.0) {
            HStack(alignment: .top, spacing: 4.0) {
                Group {
                    Image(systemName: "info.circle")
                    Text("Importer.Note", tableName: "Import")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(10.0)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 16.0))

            Button {
                Task { await save(to: albumInViewPath()) }
            } label: {
                Text("Import.ImportHere", tableName: "Import")
                    .bold()
                    .padding(4.0)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(isSearching && viewPath.isEmpty)
        }
        .padding(20.0)
    }

    func albumInViewPath() -> Album? {
        if case .album(let album) = viewPath.last {
            return album
        }
        return nil
    }

    func save(to album: Album?) async {
        await session.save(to: .albums(libraryID: DataActor.shared.collectionID,
                                       libraryName: libraryName,
                                       albumID: album?.id,
                                       albumName: album?.name))
    }
}
