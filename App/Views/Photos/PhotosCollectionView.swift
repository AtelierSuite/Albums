import Engine
import Photos
import SwiftUI

struct PhotosCollectionView: View {
    @Environment(PhotosManager.self) var photosManager
    @EnvironmentObject var navigation: NavigationManager

    @Namespace var namespace

    @State var items: [PHCollectionItem] = []
    @State var rootAssets: [PHAsset] = []
    @State var hasFetchedCollections: Bool = false
    @State var hasFetchedRootAssets: Bool = false
    @State var isFetchingRootAssets: Bool = false
    @State var searchText: String = ""

    @State var searchResults: [PHCollectionItem]?

    var filteredItems: [PHCollectionItem] {
        if searchText.isEmpty {
            return items
        }
        return searchResults ?? []
    }

    @State var isAddingAlbum: Bool = false
    @State var newAlbumName: String = ""
    @State var albumToRename: PHAssetCollection?
    @State var renameText: String = ""
    @State var albumToDelete: PHAssetCollection?
    @State var folderToDelete: PHCollectionList?
    @State var albumToMove: PHAssetCollection?
    @State var isConfirmingDeleteAlbum: Bool = false
    @State var isConfirmingDeleteFolder: Bool = false
    @State var coverRefreshID: Int = 0

    @AppStorage(photosAlbumViewStyleKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var albumStyle: AlbumViewStyle = .mosaicGrid
    @AppStorage(photosAlbumSortKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var albumSort: SortType = .nameAscending
    @AppStorage(photosAlbumColumnCountKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var albumColumnCount: Int = 4
    @AppStorage(photosPicSortKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var picSort: PhotosPicSortType = .dateCreatedDescending

    var body: some View {
        Group {
            switch photosManager.authorizationStatus {
            case .authorized, .limited:
                collectionContent
            case .denied, .restricted:
                photosAccessDeniedView
            default:
                ProgressView()
                    .task {
                        await photosManager.requestAuthorization()
                    }
            }
        }
        .overlay(alignment: .top) {
            ToastOverlayView(priority: 0)
        }
        .navigationTitle(String(localized: "ViewTitle.Photos"))
        .searchable(text: $searchText, prompt: Text("Albums.Search.Prompt", tableName: "Albums"))
        .onChange(of: searchText) { _, newValue in
            withAnimation(.smooth.speed(2.0)) {
                if newValue.isEmpty {
                    searchResults = nil
                } else {
                    searchResults = photosManager.searchAlbums(matching: newValue).sortedAlbums(by: albumSort)
                }
            }
        }
        .onChange(of: picSort) { _, _ in
            withAnimation(.smooth.speed(2.0)) {
                rootAssets.reverse()
            }
        }
        .onChange(of: albumSort) { _, newValue in
            withAnimation(.smooth.speed(2.0)) {
                items = items.sortedAlbums(by: newValue)
                searchResults = searchResults?.sortedAlbums(by: newValue)
            }
        }
        .toolbar {
            if photosManager.authorizationStatus == .authorized ||
               photosManager.authorizationStatus == .limited {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Shared.Create", systemImage: "rectangle.stack.badge.plus") {
                        isAddingAlbum = true
                    }
                }
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ToolbarItemGroup(placement: .bottomBar) {
                        photosFilterMenu
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
            }
        }
        .alert("ViewTitle.Albums.Create", isPresented: $isAddingAlbum) {
            photosNewAlbumAlert
        }
        .sheet(isPresented: Binding(
            get: { albumToRename != nil },
            set: { if !$0 { albumToRename = nil } }
        )) {
            if let collection = albumToRename {
                photosRenameAlbumSheet(collection)
            }
        }
        .sheet(isPresented: Binding(
            get: { albumToMove != nil },
            set: { if !$0 { albumToMove = nil } }
        )) {
            if let collection = albumToMove {
                photosMoveFolderSheet(collection)
            }
        }
        .confirmationDialog("Shared.DeleteConfirmation.Album",
                            isPresented: $isConfirmingDeleteAlbum, titleVisibility: .visible) {
            Button("Shared.Yes", role: .destructive) {
                confirmDeletePhotosAlbum()
            }
            Button("Shared.No", role: .cancel) {
                albumToDelete = nil
            }
        }
        .confirmationDialog("Shared.DeleteConfirmation.Album",
                            isPresented: $isConfirmingDeleteFolder, titleVisibility: .visible) {
            Button("Shared.Yes", role: .destructive) {
                confirmDeletePhotosFolder()
            }
            Button("Shared.No", role: .cancel) {
                folderToDelete = nil
            }
        }
    }

    @ViewBuilder
    private var photosFilterMenu: some View {
        Menu {
            Section(String(localized: "Albums.Albums", table: "Albums")) {
                AlbumViewStylePicker(selection: $albumStyle)
                AlbumSortPicker(selection: $albumSort)
            }
            Section(String(localized: "Albums.Pics", table: "Albums")) {
                PhotosPicOptions()
            }
        } label: {
            Label("Shared.Filter", systemImage: "line.3.horizontal.decrease")
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }
}
