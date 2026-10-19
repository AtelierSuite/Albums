import Engine
import Photos
import SwiftUI

struct MainSplitView: View {

    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ViewerManager.self) var viewer
    @Environment(PhotosManager.self) var photosManager
    @Environment(PhotosViewerManager.self) var photosViewer
    @Environment(ConcurrencyManager.self) var concurrency
    @Environment(ImageMigrationManager.self) var imageMigration
    @Namespace var namespace

    @AppStorage("PhotosModeEnabled",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var isPhotosModeEnabled: Bool = false

    @State var albums: [Album] = []
    @State var photosItems: [PHCollectionItem] = []
    @State var selectedView: ViewPath? = .collection
    @State var isMoreViewPresenting: Bool = false
    @State var isLibraryManagerPresented: Bool = false

    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false

    var body: some View {
        splitView
        .task {
            if isPhotosModeEnabled {
                photosItems = photosManager.fetchTopLevelCollections()
            } else {
                do {
                    albums = try await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)
                    await AlbumCoverCache.shared.loadCovers(for: albums)
                } catch {
                    debugPrint(error.localizedDescription)
                }
            }
        }
        .onChange(of: isPhotosModeEnabled) { _, newValue in
            selectedView = .collection
            if newValue {
                photosItems = photosManager.fetchTopLevelCollections()
            } else {
                photosItems = []
                Task {
                    do {
                        albums = try await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)
                        await AlbumCoverCache.shared.loadCovers(for: albums)
                    } catch {
                        debugPrint(error.localizedDescription)
                    }
                }
            }
        }
        .onChange(of: navigation.dataVersion) { _, _ in
            albums = []
            selectedView = .collection
            viewer.displayedPic = nil
            viewer.displayedImage = nil
            viewer.displayedThumbnail = nil
            viewer.allPics = []
            Task {
                if isPhotosModeEnabled {
                    photosItems = photosManager.fetchTopLevelCollections()
                } else {
                    do {
                        albums = try await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)
                        await AlbumCoverCache.shared.loadCovers(for: albums)
                    } catch {
                        debugPrint(error.localizedDescription)
                    }
                }
            }
        }
        .sheet(isPresented: $isMoreViewPresenting) {
            MoreView()
        }
        .sheet(isPresented: $isLibraryManagerPresented) {
            LibraryManagerSheet()
                .environmentObject(libraryManager)
                .environmentObject(navigation)
                .environment(concurrency)
                .environment(imageMigration)
        }
    }

    @ViewBuilder var splitView: some View {
#if targetEnvironment(macCatalyst)
        if openPicsInNewWindow {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 150.0, ideal: 200.0, max: 250.0)
            } detail: {
                content
            }
        } else {
            threeColumnSplit
        }
#else
        threeColumnSplit
#endif
    }

    @ViewBuilder var threeColumnSplit: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 150.0, ideal: 200.0, max: 250.0)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 300.0, ideal: 375.0, max: 500.0)
        } detail: {
            detail
        }
    }

    var sidebar: some View {
        List(selection: $selectedView) {
                Section {
                    LibrarySwitcherMenu(
                        isLibraryManagerPresented: $isLibraryManagerPresented
                    )
                }
                Section {
                    NavigationLink(value: ViewPath.collection) {
                        Label {
                            Text(isPhotosModeEnabled
                                 ? String(localized: "ViewTitle.Photos")
                                 : String(localized: "ViewTitle.Collection"))
                        } icon: {
                            Image(systemName: isPhotosModeEnabled ? "photo.on.rectangle" : "house.fill")
                        }
                    }
                    if !isPhotosModeEnabled {
                        NavigationLink(value: ViewPath.albums) {
                            Label {
                                Text("ViewTitle.Albums")
                            } icon: {
                                Image(systemName: "rectangle.stack.fill")
                            }
                        }
                        NavigationLink(value: ViewPath.pics) {
                            Label {
                                Text("ViewTitle.Pics")
                            } icon: {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                        }
                    }
#if !targetEnvironment(macCatalyst)
                    Button {
                        isMoreViewPresenting = true
                    } label: {
                        Label("ViewTitle.More", systemImage: "ellipsis")
                    }
#endif
                }
                if isPhotosModeEnabled {
                    Section {
                        ForEach(photosItems) { item in
                            switch item {
                            case .album(let collection):
                                NavigationLink(value: ViewPath.photosAlbum(
                                    album: PHAssetCollectionWrapper(collection: collection))) {
                                    Label {
                                        Text(collection.localizedTitle ?? String(
                                            localized: "Import.Albums.Untitled", table: "Import"))
                                    } icon: {
                                        Image(systemName: "rectangle.stack")
                                    }
                                }
                            case .folder(let folder):
                                NavigationLink(value: ViewPath.photosFolder(
                                    folder: PHCollectionListWrapper(collectionList: folder))) {
                                    Label {
                                        Text(folder.localizedTitle ?? String(
                                            localized: "Import.Albums.Untitled", table: "Import"))
                                    } icon: {
                                        Image(systemName: "folder")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Shared.Albums")
                    }
                } else {
                    Section {
                        ForEach(albums) { album in
                            NavigationLink(value: ViewPath.album(album: album)) {
                                Label {
                                    Text(album.name)
                                } icon: {
                                    SidebarAlbumIcon(album: album)
                                }
                            }
                        }
                    } header: {
                        Text("Shared.Albums")
                    }
                }
            }
        .listStyle(.sidebar)
#if targetEnvironment(macCatalyst)
        .environment(\.defaultMinListRowHeight, 32.0)
#endif
    }

    var content: some View {
        Group {
            switch selectedView {
            case .collection: CollectionView()
            case .albums: AlbumsView()
            case .pics: PicsView()
            case .album(let album): AlbumNavigationStack(album: album)
            case .photosAlbum(let wrapper):
                NavigationStack {
                    PhotosAlbumContentView(collection: wrapper.collection)
                }
            case .photosFolder(let wrapper):
                NavigationStack {
                    PhotosFolderView(folder: wrapper.collectionList)
                        .navigationDestination(for: ViewPath.self) { viewPath in
                            switch viewPath {
                            case .photosFolder(let innerWrapper):
                                PhotosFolderView(folder: innerWrapper.collectionList)
                            case .photosAlbum(let innerWrapper):
                                PhotosAlbumContentView(collection: innerWrapper.collection)
                            default: Color.clear
                            }
                        }
                }
            default: Color.clear
            }
        }
    }

    @ViewBuilder var detail: some View {
        if isPhotosModeEnabled {
            if let asset = photosViewer.displayedAsset {
                PhotosAssetViewer(asset: asset)
                    .id(asset.localIdentifier)
            } else {
                ContentUnavailableView("Shared.SelectAPhoto", systemImage: "photo.on.rectangle.angled")
            }
        } else {
            if let pic = viewer.displayedPic {
                PicViewer(pic: pic)
                    .id(pic.id)
            } else {
                ContentUnavailableView("Shared.SelectAPic", systemImage: "photo.on.rectangle.angled")
            }
        }
    }
}
struct SidebarAlbumIcon: View {

    var album: Album

    @State private var coverImage: Image?

    var body: some View {
        Group {
            if let coverImage {
                coverImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(uiImage: UIImage(named: "Album.Generic")!)
                    .resizable()
            }
        }
#if targetEnvironment(macCatalyst)
        .frame(width: 28.0, height: 28.0)
        .clipShape(.rect(cornerRadius: 6.0))
#else
        .frame(width: 32.0, height: 32.0)
        .clipShape(.rect(cornerRadius: 7.0))
#endif
        .onAppear {
            loadFromCache()
        }
        .onChange(of: AlbumCoverCache.shared.version) {
            loadFromCache()
        }
    }

    private func loadFromCache() {
        if let cached = AlbumCoverCache.shared.images(forAlbumID: album.id) {
            coverImage = cached.primary
        }
    }
}
