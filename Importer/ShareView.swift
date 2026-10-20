import Engine
import SwiftUI

struct ShareView: View {

    var session: SaveSession

    @State var viewPath: [ViewPath] = []
    @State var isSearching: Bool = false
    @State var libraries: [PicLibrary] = []
    @State var libraryID: String = DataActor.shared.collectionID

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
                                         session: session,
                                         isSearching: $isSearching,
                                         focusSearchOnAppear: openSearchWhenSharing)
                            .id(libraryID)
                            .toolbar {
                                if libraries.count > 1 {
                                    ToolbarItem(placement: .topBarLeading) {
                                        libraryMenu
                                    }
                                }
                            }
                            .navigationDestination(for: ViewPath.self) { viewPath in
                                if case .album(let album) = viewPath {
                                    AlbumsScrollView(title: LocalizedStringKey(album.name),
                                                     session: session,
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
            libraries = await LibrariesActor.shared.allLibraries()
                .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
            if hasDefaultAlbum, !session.items.isEmpty {
                let albumID = defaultAlbumID == "__collection__" ? nil : defaultAlbumID
                let album: Album? = if let albumID { await DataActor.shared.album(for: albumID) } else { nil }
                await save(to: album)
            }
        }
        .onChange(of: libraryID) { _, newLibraryID in
            DataActor.switchLibrary(to: newLibraryID)
            CoverCacheActor.switchLibrary(to: newLibraryID)
            AlbumCoverCache.shared.removeAllImages()
            isSearching = false
            viewPath = []
        }
        .onChange(of: viewPath) { _, newPath in
            if quickImport, case .album(let album) = newPath.last, album.albumCount() == 0 {
                Task { await save(to: album) }
            }
        }
    }

    private var libraryMenu: some View {
        Menu {
            Picker(selection: $libraryID) {
                ForEach(libraries) { library in
                    Text(displayName(for: library))
                        .tag(library.id)
                }
            } label: {
                Text("Importer.Library", tableName: "Import")
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text(currentLibraryName)
            } icon: {
                Image(systemName: "books.vertical")
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var currentLibraryName: String {
        libraries.first(where: { $0.id == libraryID }).map(displayName(for:)) ?? ""
    }

    private func displayName(for library: PicLibrary) -> String {
        if library.isDefault && library.name.isEmpty {
            return String(localized: "Importer.Library.Default", table: "Import")
        }
        return library.name
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
        let libraryID = DataActor.shared.collectionID
        let libraryName = await LibrariesActor.shared.library(for: libraryID)?.name ?? ""
        await session.save(to: .albums(libraryID: libraryID,
                                       libraryName: libraryName,
                                       albumID: album?.id,
                                       albumName: album?.name))
    }
}
