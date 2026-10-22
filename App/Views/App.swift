import BackgroundTasks
import Combine
import Engine
import StoreKit
import SwiftUI
import TipKit
import UserNotifications
import WidgetKit

@main
struct IllustMateApp: App {

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview

    @StateObject var navigation = NavigationManager()
    @StateObject var libraryManager = LibraryManager()
    @State var viewer = ViewerManager()
    @State var concurrency = ConcurrencyManager()
    @State var photosManager = PhotosManager()
    @State var photosViewer = PhotosViewerManager()
    @State var auth = AuthenticationManager()
    @State var pipManager = PictureInPictureManager()
    @State var webServer = WebServerManager()
    @State var imageMigration = ImageMigrationManager()
    @State var importManager = ImportManager.shared
    @State var isImportingBackup: Bool = false
    @State var importedURL: URL?
    @State var showLockCover: Bool = false

    @State var isShowingInternals: Bool = false
    @State var isSeedingData: Bool = false
    @State var seedCurrent: Int = 0
    @State var seedTotal: Int = 0

    @AppStorage("AppLockEnabled",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var isAppLockEnabled: Bool = false
    @AppStorage(
        "LastVersionPromptedForReview",
        store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
    ) var lastVersionPromptedForReview: String = ""
    @AppStorage(
        "LastWelcomedVersion",
        store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
    ) var lastWelcomedVersion: String = ""

    @State var isShowingWelcome: Bool = false
    @State var welcomeVersion: String = ""

    nonisolated static let widgetRefreshTaskID = "com.tsubuzaki.IllustMate.widgetRefresh"
    nonisolated static let iCloudSyncTaskID = "com.tsubuzaki.IllustMate.iCloudSync"

    private var mainContent: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                CollectionView()
            } else {
                MainSplitView()
            }
        }
        .modifier(SpotlightModifier())
        .modifier(ImportRecoveryModifier())
        .environment(importManager)
        .environmentObject(navigation)
        .environmentObject(libraryManager)
        .environment(viewer)
        .environment(concurrency)
        .environment(photosManager)
        .environment(photosViewer)
        .environment(auth)
        .environment(pipManager)
        .environment(webServer)
        .environment(imageMigration)
        .preferredColorScheme(screenshotColorScheme)
        .overlay(alignment: .bottomLeading) {
            PictureInPictureLayerView(pipManager: pipManager)
                .frame(width: 1, height: 1)
                .opacity(0.001)
        }
        .overlay(alignment: .top) {
            #if DEBUG
            if !ScreenshotSeeder.isActive {
                SyncDebugOverlay()
            }
            #endif
        }
        .overlay(alignment: .top) {
            ToastOverlayView(priority: -1, topPadding: 56.0) {
                navigation.signalDataChanged()
            }
        }
        .onAppear {
            pipManager.setup()
        }
        .task {
            UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
            #if DEBUG
            var didSeed = false
            if ScreenshotSeeder.isActive {
                ScreenshotSeeder.resetNavigation()
                ScreenshotSeeder.fixWindowSize()
                didSeed = await ScreenshotSeeder.seedIfNeeded()
                Tips.hideAllTipsForTesting()
            }
            #endif
            await libraryManager.loadLibraries()
            AlbumsShortcuts.updateAppShortcutParameters()
            #if DEBUG
            if didSeed {
                navigation.signalDataChanged()
            }
            #endif
            await imageMigration.runPendingMigrations()
            presentWelcomeIfNeeded()
            if !isShowingWelcome {
                importManager.loadInterruptedJobs()
            }
            do {
                // TODO: Tips are broken in iOS 26 thanks to SwiftUI bug
                //       Will include everything for now until Apple fixes it
                try Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.applicationDefault)
                ])
            } catch {
                debugPrint(error.localizedDescription)
            }
            await migratePreferencesFromUserDefaults()
            DatabaseMigrator.markMigrationComplete()
            await libraryManager.reconcileWithICloud()
            await RecentlyDeleted.purgeExpired(in: libraryManager.currentLibrary.id)
            await SyncManager.shared.refresh()
        }
        .onChange(of: libraryManager.currentLibrary.id) { _, newID in
            Task {
                await imageMigration.runIfNeeded(for: newID)
                await RecentlyDeleted.purgeExpired(in: newID)
                await SyncManager.shared.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyRemoteChanges)) { _ in
            navigation.signalDataChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataActorDidMutateLocally)) { note in
            if let collectionID = note.object as? String {
                Task { @MainActor in
                    SyncManager.shared.schedulePush(forLibrary: collectionID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyLibraryChanges)) { note in
            let removedLibraryIDs = note.object as? [String] ?? []
            Task { await libraryManager.reloadList(removedLibraryIDs: removedLibraryIDs) }
        }
        .onOpenURL { url in
            if url.pathExtension == "pics" {
                importedURL = url
            } else if url.scheme == "picmate", url.host == "album",
                      let albumID = url.pathComponents.dropFirst().first {
                Task {
                    await open(.album(id: albumID, libraryID: libraryManager.currentLibrary.id))
                }
            }
            if url.scheme == "picmate", url.host == "internals" {
                isShowingInternals = true
            }
            if url.scheme == "picmate", url.host == "entrophyrocks" {
                handleSampleDataURL(url)
            }
            if url.scheme == "picmate", url.host == "reonboard" {
                presentWelcome()
            }
        }
        .onChange(of: IntentNavigator.shared.pendingDestination, initial: true) { _, _ in
            openPendingIntentDestination()
        }
        .onChange(of: libraryManager.hasLoadedLibraries) { _, _ in
            openPendingIntentDestination()
        }
        .onChange(of: importedURL) { _, newValue in
            if newValue != nil {
                isImportingBackup = true
            }
        }
        .sheet(isPresented: $isImportingBackup) {
            if let importedURL { discardInboxCopy(of: importedURL) }
            importedURL = nil
        } content: {
            if let importedURL {
                RestoreBackupView(backupURL: importedURL)
                    .environmentObject(navigation)
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $isShowingInternals) {
            NavigationStack {
                LabsFileExplorerView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) {
                                isShowingInternals = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $isSeedingData) {
            StatusView(type: .inProgress,
                       title: .custom("Generating sample data…"),
                       currentCount: seedCurrent,
                       totalCount: seedTotal)
                .phonePresentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageMigration.isMigrating },
            set: { _ in }
        )) {
            ImageMigrationView(manager: imageMigration)
        }
        .sheet(isPresented: $isShowingWelcome) {
            importManager.loadInterruptedJobs()
        } content: {
            WelcomeView {
                lastWelcomedVersion = welcomeVersion
                isShowingWelcome = false
            }
        }
    }

    func discardInboxCopy(of url: URL) {
        // Files the system copies into Documents/Inbox are never cleaned up for us.
        guard let documents = try? FileManager.default.url(for: .documentDirectory,
                                                           in: .userDomainMask,
                                                           appropriateFor: nil, create: false) else {
            return
        }
        let inbox = documents.appendingPathComponent("Inbox").standardizedFileURL.path
        guard url.standardizedFileURL.deletingLastPathComponent().path == inbox else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func handleSampleDataURL(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func count(_ name: String) -> Int? {
            components?.queryItems?.first { $0.name == name }?.value.flatMap { Int($0) }
        }
        let picCount = count("pics") ?? Int.random(in: 11000...15000)
        let albumCount = count("albums") ?? Int.random(in: 20...60)
        let legacyBlobs = (count("legacy") ?? 0) != 0
        Task { @MainActor in
            seedCurrent = 0
            seedTotal = picCount
            isSeedingData = true
            UIApplication.shared.isIdleTimerDisabled = true
            await SampleDataGenerator.generate(
                picCount: picCount, albumCount: albumCount,
                into: DataActor.shared, legacyBlobs: legacyBlobs
            ) { completed, total in
                seedCurrent = completed
                seedTotal = total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            isSeedingData = false
            navigation.signalDataDeleted()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                mainContent
                if showLockCover {
                    LockScreenView()
                        .environment(auth)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showLockCover)
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .background {
                    WidgetCenter.shared.reloadTimelines(ofKind: "Photostand")
                    WidgetCenter.shared.reloadTimelines(ofKind: "PhotoGrid")
                    scheduleWidgetRefresh()
                    scheduleICloudSync()
                    webServer.stop()
                    AlbumsShortcuts.updateAppShortcutParameters()
                }
                if newValue == .active {
                    Task { await SyncManager.shared.refresh() }
                    let currentVersion = Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? ""
                    if ViewerManager.picOpenCount >= 6,
                       currentVersion != lastVersionPromptedForReview {
                        lastVersionPromptedForReview = currentVersion
                        requestReview()
                    }
                }
                if isAppLockEnabled {
                    switch newValue {
                    case .inactive:
                        showLockCover = true
                    case .background:
                        auth.lock()
                        showLockCover = true
                    case .active:
                        if auth.isUnlocked {
                            showLockCover = false
                        } else {
                            auth.authenticate()
                        }
                    @unknown default:
                        break
                    }
                }
            }
            .onChange(of: auth.isUnlocked) { _, isUnlocked in
                if isUnlocked {
                    showLockCover = false
                }
            }
        }
        .backgroundTask(.appRefresh(IllustMateApp.widgetRefreshTaskID)) {
            WidgetCenter.shared.reloadTimelines(ofKind: "Photostand")
            WidgetCenter.shared.reloadTimelines(ofKind: "PhotoGrid")
            scheduleWidgetRefresh()
        }
        .backgroundTask(.appRefresh(IllustMateApp.iCloudSyncTaskID)) {
            scheduleICloudSync()
            await SyncManager.shared.backgroundSync()
        }
#if targetEnvironment(macCatalyst)
        .commands {
            MacCommands(viewer: viewer, photosViewer: photosViewer)
        }
#endif
#if targetEnvironment(macCatalyst)
        WindowGroup(for: ViewerWindowValue.self) { $value in
            if let value {
                ViewerWindowContent(value: value)
                    .environmentObject(navigation)
                    .environmentObject(libraryManager)
                    .environment(concurrency)
                    .environment(photosManager)
                    .environment(auth)
                    .environment(pipManager)
                    .environment(webServer)
                    .environment(imageMigration)
            }
        }

        WindowGroup("ViewTitle.Settings", id: settingsWindowID) {
            SettingsView()
                .environmentObject(navigation)
                .environmentObject(libraryManager)
                .environment(viewer)
                .environment(concurrency)
                .environment(photosManager)
                .environment(photosViewer)
                .environment(auth)
                .environment(pipManager)
                .environment(webServer)
                .environment(imageMigration)
        }
        .defaultSize(width: 540.0, height: 640.0)
#endif
    }
}

extension IllustMateApp {

    nonisolated func scheduleWidgetRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: IllustMateApp.widgetRefreshTaskID)
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 24, to: .now)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated func scheduleICloudSync() {
        let request = BGAppRefreshTaskRequest(identifier: IllustMateApp.iCloudSyncTaskID)
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
        try? BGTaskScheduler.shared.submit(request)
    }

    var screenshotColorScheme: ColorScheme? {
        #if DEBUG
        ScreenshotSeeder.isActive ? .dark : nil
        #else
        nil
        #endif
    }

    func openPendingIntentDestination() {
        guard libraryManager.hasLoadedLibraries,
              let destination = IntentNavigator.shared.pendingDestination else { return }
        IntentNavigator.shared.pendingDestination = nil
        Task {
            await open(destination)
        }
    }

    func open(_ destination: IntentNavigator.Destination) async {
        switch destination {
        case .library(let libraryID):
            guard let library = await LibrariesActor.shared.library(for: libraryID) else { return }
            showLibrary(library)
        case .album(let albumID, let libraryID):
            guard let library = await LibrariesActor.shared.library(for: libraryID),
                  let album = await DataActor.instance(for: libraryID).album(for: albumID) else { return }
            showLibrary(library)
            try? await Task.sleep(for: .milliseconds(250))
            navigation.push(.album(album: album), for: .collection)
        }
    }

    func showLibrary(_ library: PicLibrary) {
        if library.id != libraryManager.currentLibrary.id || libraryManager.isPhotosModeEnabled {
            libraryManager.switchLibrary(to: library)
            navigation.signalDataChanged()
        }
        navigation.popAll()
        if UIDevice.current.userInterfaceIdiom == .phone {
            navigation.collectionTabPath = [.library(id: library.id)]
        }
    }

    func presentWelcomeIfNeeded() {
        #if DEBUG
        guard !ScreenshotSeeder.isActive else { return }
        #endif
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        guard WelcomeView.shouldShow(
            currentVersion: currentVersion,
            lastSeenVersion: lastWelcomedVersion
        ) else { return }
        presentWelcome()
    }

    func presentWelcome() {
        welcomeVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        isShowingWelcome = true
    }

    func migratePreferencesFromUserDefaults() async {
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        guard let defaults else { return }

        let hasAlbumSort = defaults.object(forKey: "AlbumSort") != nil
        let hasPicSort = defaults.object(forKey: "PicSortType") != nil
        let hasAlbumStyle = defaults.object(forKey: "AlbumViewStyle") != nil
        let hasAlbumColumnCount = defaults.object(forKey: "AlbumColumnCount") != nil
        let hasPicColumnCount = defaults.object(forKey: "PicColumnCount") != nil
        let hasHideSectionHeaders = defaults.object(forKey: "HideSectionHeaders") != nil

        guard hasAlbumSort || hasPicSort || hasAlbumStyle
                || hasAlbumColumnCount || hasPicColumnCount
                || hasHideSectionHeaders else {
            return
        }

        let albumSort = defaults.string(forKey: "AlbumSort") ?? AlbumPreferences.defaults.albumSort
        let albumViewStyle = defaults.string(forKey: "AlbumViewStyle") ?? AlbumPreferences.defaults.albumViewStyle
        let albumColumnCount = hasAlbumColumnCount
            ? defaults.integer(forKey: "AlbumColumnCount")
            : AlbumPreferences.defaults.albumColumnCount
        let picSort = defaults.string(forKey: "PicSortType") ?? AlbumPreferences.defaults.picSort
        let picColumnCount = hasPicColumnCount
            ? defaults.integer(forKey: "PicColumnCount")
            : AlbumPreferences.defaults.picColumnCount
        let hideSectionHeaders = hasHideSectionHeaders
            ? defaults.bool(forKey: "HideSectionHeaders")
            : AlbumPreferences.defaults.hideSectionHeaders

        var albumIDs = await DataActor.shared.allAlbumIDs()
        albumIDs.insert("__root__", at: 0)
        for albumID in albumIDs {
            let prefs = AlbumPreferences(
                albumID: albumID,
                albumSort: albumSort,
                albumViewStyle: albumViewStyle,
                albumColumnCount: albumColumnCount,
                picSort: picSort,
                picColumnCount: picColumnCount,
                hideSectionHeaders: hideSectionHeaders
            )
            await DataActor.shared.insertPreferencesForMigration(prefs)
        }

        defaults.removeObject(forKey: "AlbumSort")
        defaults.removeObject(forKey: "PicSortType")
        defaults.removeObject(forKey: "AlbumViewStyle")
        defaults.removeObject(forKey: "AlbumColumnCount")
        defaults.removeObject(forKey: "PicColumnCount")
        defaults.removeObject(forKey: "HideSectionHeaders")
    }
}

#if targetEnvironment(macCatalyst)
struct MacCommands: Commands {

    var viewer: ViewerManager
    var photosViewer: PhotosViewerManager

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.albumViewOptions) private var albumViewOptions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("ViewTitle.Settings") {
                openWindow(id: settingsWindowID)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            if let albumViewOptions {
                Menu(String(localized: "Albums.Albums", table: "Albums")) {
                    albumOptions(albumViewOptions)
                }
                Menu(String(localized: "Albums.Pics", table: "Albums")) {
                    picOptions(albumViewOptions)
                }
                Toggle(String(localized: "Albums.HideHeaders", table: "Albums"),
                       isOn: albumViewOptions.hideSectionHeaders)
                Divider()
            }
            Button("Command.PreviousPic") {
                viewer.navigateToPrevious()
                photosViewer.navigateToPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!viewer.hasPrevious && !photosViewer.hasPrevious)

            Button("Command.NextPic") {
                viewer.navigateToNext()
                photosViewer.navigateToNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!viewer.hasNext && !photosViewer.hasNext)
        }
    }

    @ViewBuilder
    private func albumOptions(_ options: AlbumViewOptions) -> some View {
        Picker(String(localized: "Albums.Style", table: "Albums"),
               selection: options.albumStyle.animation(.smooth.speed(2.0))) {
            Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                  systemImage: "square.grid.2x2")
                .tag(ViewStyle.grid)
            Label(String(localized: "Albums.Style.List", table: "Albums"),
                  systemImage: "list.bullet")
                .tag(ViewStyle.list)
            Label(String(localized: "Albums.Style.Carousel", table: "Albums"),
                  systemImage: "rectangle.on.rectangle")
                .tag(ViewStyle.carousel)
        }
        Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: options.albumSort) {
            Text("Shared.Sort.Name.Ascending")
                .tag(SortType.nameAscending)
            Text("Shared.Sort.Name.Descending")
                .tag(SortType.nameDescending)
            Text("Shared.Sort.PicCount.Ascending")
                .tag(SortType.sizeAscending)
            Text("Shared.Sort.PicCount.Descending")
                .tag(SortType.sizeDescending)
        }
        .pickerStyle(.menu)
        if options.albumStyle.wrappedValue == .grid {
            GridSizePicker(selection: options.albumColumnCount, sizes: [2, 3, 4, 5])
        }
    }

    @ViewBuilder
    private func picOptions(_ options: AlbumViewOptions) -> some View {
        Picker(String(localized: "Albums.Style", table: "Albums"),
               selection: options.picStyle.animation(.smooth.speed(2.0))) {
            Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                  systemImage: "square.grid.2x2")
                .tag(ViewStyle.grid)
            Label(String(localized: "Albums.Style.Masonry", table: "Albums"),
                  systemImage: "rectangle.3.offgrid")
                .tag(ViewStyle.masonry)
        }
        Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: options.picSort) {
            Text("Shared.Sort.DateAdded.Ascending")
                .tag(PicSortType.dateAddedAscending)
            Text("Shared.Sort.DateAdded.Descending")
                .tag(PicSortType.dateAddedDescending)
            Text("Shared.Sort.Name.Ascending")
                .tag(PicSortType.nameAscending)
            Text("Shared.Sort.Name.Descending")
                .tag(PicSortType.nameDescending)
            Text("Shared.Sort.ProminentColor")
                .tag(PicSortType.prominentColor)
        }
        .pickerStyle(.menu)
    }
}
#endif
