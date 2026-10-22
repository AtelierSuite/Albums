import Engine
import Photos
import SwiftUI

struct PhotosFolderView: View {

    @Environment(PhotosManager.self) var photosManager

    let folder: PHCollectionList

    @AppStorage("PhotosNestedAlbumsEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isNestedAlbumsEnabled: Bool = false

    @Namespace var namespace

    @State var items: [PHCollectionItem] = []
    @State var ownPicsFetchResult: PHFetchResult<PHAsset>?
    @State var hasFetched: Bool = false
    @State var searchText: String = ""

    @State var searchResults: [PHCollectionItem]?

    var filteredItems: [PHCollectionItem] {
        if searchText.isEmpty {
            return items
        }
        return searchResults ?? []
    }

    @State var albumToRename: PHAssetCollection?
    @State var renameText: String = ""
    @State var albumToDelete: PHAssetCollection?
    @State var folderToDelete: PHCollectionList?
    @State var albumToMove: PHAssetCollection?
    @State var isConfirmingDeleteAlbum: Bool = false
    @State var isConfirmingDeleteFolder: Bool = false
    @State var isAddingAlbum: Bool = false
    @State var newAlbumName: String = ""
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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0.0) {
                if !filteredItems.isEmpty {
                    albumsSection
                    if searchText.isEmpty {
                        Spacer()
                            .frame(height: 20.0)
                    }
                }

                if searchText.isEmpty,
                   isNestedAlbumsEnabled, let fetchResult = ownPicsFetchResult, fetchResult.count > 0 {
                    picsSection(fetchResult: fetchResult)
                }
            }
            .padding([.top], 20.0)
        }
        .navigationTitle(folder.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
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
            fetchContent()
        }
        .onChange(of: albumSort) { _, newValue in
            withAnimation(.smooth.speed(2.0)) {
                items = items.sortedAlbums(by: newValue)
                searchResults = searchResults?.sortedAlbums(by: newValue)
            }
        }
        .toolbar {
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
        .onAppear {
            if !hasFetched {
                fetchContent()
            }
        }
        .alert("ViewTitle.Albums.Create", isPresented: $isAddingAlbum) {
            photosNewAlbumInFolderAlert
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
            if isNestedAlbumsEnabled, ownPicsFetchResult != nil {
                Section(String(localized: "Albums.Pics", table: "Albums")) {
                    PhotosPicOptions()
                }
            }
        } label: {
            Label("Shared.Filter", systemImage: "line.3.horizontal.decrease")
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }
}
