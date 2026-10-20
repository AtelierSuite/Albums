import Engine
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable:next type_body_length
struct AlbumView: View {

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ViewerManager.self) var viewer

    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false
    @AppStorage(importShowNotificationKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var showImportNotification: Bool = true
    @AppStorage(picViewStyleKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var picViewStyle: ViewStyle = .grid

    @Namespace var namespace

    @State var currentAlbum: Album?
    @State var albums: [Album] = []
    @State var hasFetchedAlbums: Bool = false
    @State var isConfirmingDeleteAlbum: Bool = false
    @State var albumPendingDeletion: Album?
    @State var isAddingAlbum: Bool = false
    @State var newAlbumName: String = ""
    @State var albumToRename: Album?
    @State var renameAlbumText: String = ""
    @State var albumSort: SortType = .nameAscending
    @State var albumSortState: SortType = .nameAscending
    @State var albumStyle: ViewStyle = .grid
    @State var albumStyleState: ViewStyle = .grid

    @State var pics: [Pic] = []
    @State var picCount: Int = 0
    @State var hasFetchedPicCount: Bool = false
    @State var hasFetchedPics: Bool = false
    @State var isConfirmingDeletePic: Bool = false
    @State var isConfirmingDeleteSelectedPics: Bool = false
    @State var picPendingDeletion: Pic?
    @State var isSelectingPics: Bool = false
    @State var selectedPics: [Pic] = []
    @State var isBrowsingAlbums: Bool = false
    @State var isBrowsingFolders: Bool = false
    @State var isFileImporterPresented: Bool = false
    @State var isFileImportSheetPresented: Bool = false
    @State var isPhotosPickerPresented: Bool = false
    @State var isVideosPickerPresented: Bool = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var selectedVideoItems: [PhotosPickerItem] = []
    @State var isImportingPhotos: Bool = false
    @State var importCurrentCount: Int = 0
    @State var importTotalCount: Int = 0
    @State var picSortType: PicSortType = .dateAddedDescending
    @State var columnCount: Int = 4
    @State var albumColumnCount: Int = 4
    @State var hideSectionHeaders: Bool = false

    @State var totalAlbumCount: Int = 0
    @State var backgroundImage: UIImage?
    @State var lastRefreshTime: Date = .distantPast
    @State var searchText: String = ""
    @State var searchResults: [Album]?
    @State var searchTask: Task<Void, Never>?
    @State var isDuplicateCheckerPresented: Bool = false
    @State var isIntelligentSortPresented: Bool = false
    @State var hasCompletedInitialLoad: Bool = false
    @State var movePayload: LibraryMovePayload?
    @State var highlightedPicID: String?

    var displayedAlbums: [Album] {
        searchResults ?? albums
    }

    var navigationTitleText: String {
        currentAlbum?.name ?? libraryManager.displayName(for: libraryManager.currentLibrary)
    }

    var navigationSubtitleText: String {
        if currentAlbum != nil {
            return libraryManager.currentLibrary.name
        }
        return ""
    }

    var body: some View {
        contentWithObservers
            .overlay(alignment: .top) {
                ToastOverlayView(priority: 0) {
                    navigation.signalDataChanged()
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationSubtitle(Text(verbatim: navigationSubtitleText))
            .searchable(text: $searchText, prompt: Text("Albums.Search.Prompt", tableName: "Albums"))
            .modifier(AlbumViewOptionsFocusModifier(options: AlbumViewOptions(
                albumStyle: $albumStyleState,
                albumSort: $albumSortState,
                albumColumnCount: $albumColumnCount,
                picSort: $picSortType,
                picColumnCount: $columnCount,
                picStyle: $picViewStyle,
                hideSectionHeaders: $hideSectionHeaders
            )))
    }

    var contentWithReveal: some View {
        ScrollViewReader { proxy in
            mainContent
                .onChange(of: hasFetchedPics) { _, _ in
                    revealPicIfNeeded(with: proxy)
                }
                .onChange(of: navigation.picRevealRequest) { _, _ in
                    revealPicIfNeeded(with: proxy)
                }
        }
    }

    var contentWithSheets: some View {
        contentWithReveal
            .toolbar {
                toolbarContent
            }
            .modifier(AlbumViewSheets(
                isAddingAlbum: $isAddingAlbum,
                newAlbumName: $newAlbumName,
                albumToRename: $albumToRename,
                renameAlbumText: $renameAlbumText,
                isBrowsingAlbums: $isBrowsingAlbums,
                isBrowsingFolders: $isBrowsingFolders,
                isImportingPhotos: $isImportingPhotos,
                importCurrentCount: importCurrentCount,
                importTotalCount: importTotalCount,
                currentAlbum: currentAlbum,
                onAlbumDismiss: { refreshAlbumsAndSet() },
                onBrowseAlbumsDismiss: {
                    Task.detached(priority: .userInitiated) {
                        await refreshData()
                    }
                },
                onImportDismiss: {
                    importCurrentCount = 0
                    importTotalCount = 0
                    Task.detached(priority: .userInitiated) {
                        await refreshData()
                    }
                }
            ))
            .modifier(AlbumMediaImportModifier(
                isPhotosPickerPresented: $isPhotosPickerPresented,
                selectedPhotoItems: $selectedPhotoItems,
                isVideosPickerPresented: $isVideosPickerPresented,
                selectedVideoItems: $selectedVideoItems,
                isFileImporterPresented: $isFileImporterPresented,
                isFileImportSheetPresented: $isFileImportSheetPresented,
                onPhotosSelected: { importSelectedPhotos($0) },
                onVideosSelected: { importSelectedVideos($0) },
                onFilesImported: { importLoadedFiles($0) }
            ))
            .sheet(isPresented: $isDuplicateCheckerPresented) {
                Group {
                    if let currentAlbum {
                        DuplicateScanView(scanScope: .album(currentAlbum))
                    } else {
                        DuplicateScanView(scanScope: .picsNotInAlbums)
                    }
                }
                .phonePresentationDetents([.medium, .large])
                .interactiveDismissDisabled()
            }
            .onChange(of: isDuplicateCheckerPresented) { _, isPresented in
                if !isPresented {
                    refreshPicsAndSet()
                }
            }
            .sheet(isPresented: $isIntelligentSortPresented) {
                Group {
                    if let currentAlbum {
                        IntelligentSortView(scope: .album(currentAlbum))
                    } else {
                        IntelligentSortView(scope: .root)
                    }
                }
                .phonePresentationDetents([.medium, .large])
                .interactiveDismissDisabled()
            }
            .onChange(of: isIntelligentSortPresented) { _, isPresented in
                if !isPresented {
                    refreshPicsAndSet()
                }
            }
            .sheet(item: $movePayload) { payload in
                MoveToLibrarySheet(payload: payload,
                                   sourceID: DataActor.shared.collectionID) {
                    switch payload {
                    case .album: refreshAlbumsAndSet()
                    case .pics: refreshDataAfterPicMoved()
                    }
                }
                .environmentObject(libraryManager)
            }
            .modifier(AlbumViewDialogs(
                isConfirmingDeleteAlbum: $isConfirmingDeleteAlbum,
                isConfirmingDeletePic: $isConfirmingDeletePic,
                isConfirmingDeleteSelectedPics: $isConfirmingDeleteSelectedPics,
                albumPendingDeletion: $albumPendingDeletion,
                picPendingDeletion: $picPendingDeletion,
                selectedPicsCount: selectedPics.count,
                onConfirmDeleteAlbum: { confirmDeleteAlbum(deletingContents: $0) },
                onConfirmDeletePic: { confirmDeletePic() }
            ))
    }

    var contentWithObservers: some View {
        contentWithSheets
            .task {
                await loadPreferences()
                albumStyleState = albumStyle
                albumSortState = albumSort
                await refreshData()
                hasCompletedInitialLoad = true
            }
            .task(id: currentAlbum.map { "\($0.id)-\($0.hasCoverPhoto)-\($0.coverPhoto != nil)" }) {
                await updateBackgroundImage()
            }
            .onChange(of: albumStyleState) { _, newValue in
                albumStyle = newValue
                guard hasCompletedInitialLoad else { return }
                savePreference()
            }
            .onChange(of: albumSortState) { _, newValue in
                albumSort = newValue
            }
            .onChange(of: albumSort) { _, _ in
                guard hasCompletedInitialLoad else { return }
                savePreference()
                refreshAlbumsAndSet()
            }
            .onChange(of: picSortType) { _, _ in
                guard hasCompletedInitialLoad else { return }
                savePreference()
                refreshPicsAndSet()
            }
            .onChange(of: columnCount) { _, _ in
                guard hasCompletedInitialLoad else { return }
                savePreference()
            }
            .onChange(of: albumColumnCount) { _, _ in
                guard hasCompletedInitialLoad else { return }
                savePreference()
            }
            .onChange(of: hideSectionHeaders) { _, _ in
                guard hasCompletedInitialLoad else { return }
                savePreference()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    let now = Date.now
                    guard now.timeIntervalSince(lastRefreshTime) > 5.0 else { return }
                    lastRefreshTime = now
                    Task.detached(priority: .userInitiated) {
                        await refreshData()
                    }
                }
            }
            .onChange(of: navigation.dataVersion) { _, _ in
                Task.detached(priority: .userInitiated) {
                    await reloadPreferencesAndRefreshData()
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                if newValue.isEmpty {
                    searchResults = nil
                } else {
                    searchTask = Task.detached(priority: .userInitiated) {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await searchAlbums(matching: newValue)
                    }
                }
            }
    }

    var mainContent: some View {
        ZStack {
            if let backgroundImage {
                Canvas { context, size in
                    let image = context.resolve(Image(uiImage: backgroundImage))
                    let imageSize = image.size
                    let scale = max(size.width / imageSize.width,
                                    size.height / imageSize.height)
                    let drawSize = CGSize(width: imageSize.width * scale,
                                          height: imageSize.height * scale)
                    let origin = CGPoint(x: (size.width - drawSize.width) / 2,
                                         y: (size.height - drawSize.height) / 2)
                    context.opacity = 0.25
                    context.draw(image, in: CGRect(origin: origin, size: drawSize))
                }
                .ignoresSafeArea()
                .transition(.opacity.animation(.smooth.speed(2.0)))
            }

            if hideSectionHeaders && searchText.isEmpty
                && hasFetchedAlbums && displayedAlbums.isEmpty
                && hasFetchedPicCount && picCount == 0 {
                ContentUnavailableView(
                    String(localized: "Albums.Empty", table: "Albums"),
                    systemImage: "photo.on.rectangle.angled"
                )
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0.0) {
                        if !isSelectingPics {
                            VStack(alignment: .leading, spacing: 0.0) {
                                albumSection
                                if !searchText.isEmpty {
                                    if displayedAlbums.isEmpty {
                                        Text("Albums.NoSearchResults", tableName: "Albums")
                                            .foregroundStyle(.secondary)
                                            .padding(20.0)
                                    }
                                } else if !hideSectionHeaders || !displayedAlbums.isEmpty {
                                    Spacer()
                                        .frame(height: 20.0)
                                }
                            }
                            .transition(.opacity.animation(.smooth.speed(2.0)))
                        }
                        if searchText.isEmpty {
                            picsSection
                        }
                    }
                    .padding(.top, (hideSectionHeaders && displayedAlbums.isEmpty) ? 0.0 : 20.0)
                    .animation(.smooth.speed(2.0), value: hideSectionHeaders)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .dropDestination(for: Drop.self) { items, _ in
            importDrops(items)
        }
    }
}
