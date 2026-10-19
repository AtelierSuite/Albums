import Engine
import SwiftUI

struct AlbumsView: View {

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var navigation: NavigationManager
    @Environment(ViewerManager.self) var viewer

    @Namespace var namespace

    @State var albums: [Album] = []
    @State private var lastDataVersion: Int = -1
    @AppStorage(wrappedValue: ViewStyle.grid, "AlbumViewStyle",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var style: ViewStyle

    @State var viewerManager = ViewerManager()

    var body: some View {
        ZStack {
            NavigationStack(path: $navigation.albumsTabPath) {
                ScrollView(.vertical) {
                    AlbumsSection(albums: albums, style: $style,
                                  isKeptOffline: { OfflineAlbums.contains($0.id) },
                                  onToggleOffline: {
                                      OfflineAlbums.toggle($0.id, in: DataActor.shared.collectionID)
                                  }) { _ in
                        // TODO: Move menu support in macOS Albums view
                    }
                }
                .navigationDestination(for: ViewPath.self) { viewPath in
                    switch viewPath {
                    case .album(let album):
                        AlbumView(currentAlbum: album)
                    case .picViewer(let namespace):
                        if let displayedPic = viewer.displayedPic {
                            if #available(iOS 18, *) {
                                PicViewer(pic: displayedPic)
                                    .navigationTransition(.zoom(
                                        sourceID: viewer.displayedPicID,
                                        in: namespace))
                            } else {
                                PicViewer(pic: displayedPic)
                            }
                        }
                    case .picViewerRestore:
                        if let displayedPic = viewer.displayedPic {
                            PicViewer(pic: displayedPic)
                        }
                    default: Color.clear
                    }
                }
                .toolbar {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(alignment: .center, spacing: 8.0) {
                                Text("\(albums.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("ViewTitle.Albums")
            }
        }
        .onAppear {
            refreshAlbumsIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                refreshAlbumsIfNeeded()
            }
        }
        .onChange(of: navigation.dataVersion) { _, _ in
            refreshAlbumsIfNeeded()
        }
    }

    func refreshAlbumsIfNeeded() {
        let currentVersion = navigation.dataVersion
        guard currentVersion != lastDataVersion || albums.isEmpty else { return }
        lastDataVersion = currentVersion
        Task.detached(priority: .userInitiated) {
            do {
                let albums = try await DataActor.shared.albumsWithCounts(sortedBy: .nameAscending)
                await MainActor.run {
                    doWithAnimation {
                        self.albums = albums
                    }
                }
                await AlbumCoverCache.shared.loadCovers(for: albums)
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
