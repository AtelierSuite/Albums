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
                NavigationStack(path: $viewPath) {
                    AlbumsScrollView(title: "ViewTitle.Importer",
                                     session: session,
                                     isSearching: $isSearching,
                                     focusSearchOnAppear: openSearchWhenSharing,
                                     reloadID: libraryID) {
                        if libraries.count > 1 {
                            libraryChips
                        }
                    }
                        .safeAreaBar(edge: .bottom) { importButton }
                        .navigationDestination(for: ViewPath.self) { viewPath in
                            if case .album(let album) = viewPath {
                                AlbumsScrollView(title: LocalizedStringKey(album.name),
                                                 session: session,
                                                 parentAlbum: album,
                                                 isSearching: $isSearching)
                                    .safeAreaBar(edge: .bottom) { importButton }
                            } else {
                                Color.clear
                            }
                        }
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
        .onChange(of: viewPath) { _, newPath in
            if quickImport, case .album(let album) = newPath.last, album.albumCount() == 0 {
                Task { await save(to: album) }
            }
        }
    }

    private var libraryChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8.0) {
                    HStack(spacing: 8.0) {
                        ForEach(libraries) { library in
                            if library.id == libraryID {
                                libraryChip(for: library, proxy: proxy)
                                    .buttonStyle(.glassProminent)
                                    .accessibilityAddTraits(.isSelected)
                            } else {
                                libraryChip(for: library, proxy: proxy)
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20.0)
                .padding(.vertical, 4.0)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(libraryID, anchor: .center)
            }
        }
        .padding(.top, 8.0)
    }

    private func libraryChip(for library: PicLibrary, proxy: ScrollViewProxy) -> some View {
        Button {
            select(library)
            withAnimation(.smooth) {
                proxy.scrollTo(library.id, anchor: .center)
            }
        } label: {
            Text(displayName(for: library))
                .lineLimit(1)
        }
        .buttonBorderShape(.capsule)
        .id(library.id)
    }

    private func select(_ library: PicLibrary) {
        guard library.id != libraryID else { return }
        DataActor.switchLibrary(to: library.id)
        CoverCacheActor.switchLibrary(to: library.id)
        AlbumCoverCache.shared.removeAllImages()
        isSearching = false
        viewPath = []
        libraryID = library.id
    }

    private func displayName(for library: PicLibrary) -> String {
        if library.isDefault && library.name.isEmpty {
            return String(localized: "Importer.Library.Default", table: "Import")
        }
        return library.name
    }

    private var importButton: some View {
        VStack(spacing: 12.0) {
            SharedItemsStrip(items: session.items)

            Button {
                Task { await save(to: albumInViewPath()) }
            } label: {
                Text("Import.ImportHere", tableName: "Import")
                    .bold()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
            .disabled(isSearching && viewPath.isEmpty)
            .padding(.horizontal, 20.0)
        }
        .padding(.vertical, 12.0)
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
