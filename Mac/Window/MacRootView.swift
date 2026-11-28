import Engine
import StoreKit
import SwiftUI
import TipKit
import UserNotifications

struct MacRootView: View {

    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ImageMigrationManager.self) var imageMigration
    @Environment(ImportManager.self) var importManager
    @Environment(MacOpenRequests.self) var openRequests
    @Environment(PictureInPictureManager.self) var pipManager
    @Environment(\.appearsActive) var appearsActive
    @Environment(\.requestReview) var requestReview

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
    @State var backupFile: BackupFile?
    @State var isShowingInternals: Bool = false
    @State var isSeedingData: Bool = false
    @State var seedCurrent: Int = 0
    @State var seedTotal: Int = 0

    var body: some View {
        MainSplitView()
            .modifier(SpotlightModifier())
            .modifier(ContentCredentialsModifier())
            .modifier(ImportRecoveryModifier())
            .overlay(alignment: .top) {
                ToastOverlayView(priority: -1, topPadding: 56.0) {
                    navigation.signalDataChanged()
                }
            }
            .overlay(alignment: .bottomLeading) {
                PictureInPictureLayerView(pipManager: pipManager)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
            }
            .onAppear {
                pipManager.setup()
            }
            .task {
                UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                await libraryManager.loadLibraries()
                AlbumsShortcuts.updateAppShortcutParameters()
                await imageMigration.runPendingMigrations()
                presentWelcomeIfNeeded()
                if !isShowingWelcome {
                    importManager.loadInterruptedJobs()
                }
                try? Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.applicationDefault)
                ])
                await DeepLinkRouter.migratePreferencesFromUserDefaults()
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
            .onChange(of: appearsActive) { _, isActive in
                if isActive {
                    promptForReviewIfNeeded()
                } else {
                    AlbumsShortcuts.updateAppShortcutParameters()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyRemoteChanges)) { note in
                for albumID in note.object as? [String] ?? [] {
                    AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
                }
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
            .onChange(of: openRequests.urls, initial: true) { _, urls in
                guard !urls.isEmpty else { return }
                openRequests.urls.removeAll()
                urls.forEach(handle)
            }
            .onChange(of: IntentNavigator.shared.pendingDestination, initial: true) { _, _ in
                openPendingIntentDestination()
            }
            .onChange(of: libraryManager.hasLoadedLibraries) { _, _ in
                openPendingIntentDestination()
            }
            .sheet(item: $backupFile) { file in
                RestoreBackupView(backupURL: file.url)
                    .environmentObject(navigation)
                    .macSheetSizing()
            }
            .sheet(isPresented: $isShowingInternals) {
                NavigationStack {
                    LabsFileExplorerView()
                        .toolbar {
                            ToolbarItem(placement: .sheetLeading) {
                                Button(role: .close) {
                                    isShowingInternals = false
                                }
                            }
                        }
                }
                .macSheetSizing()
            }
            .sheet(isPresented: $isSeedingData) {
                StatusView(type: .inProgress,
                           title: .custom("Generating sample data…"),
                           currentCount: seedCurrent,
                           totalCount: seedTotal)
                    .frame(width: 360.0, height: 240.0)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: Binding(
                get: { imageMigration.isMigrating },
                set: { _ in }
            )) {
                ImageMigrationView(manager: imageMigration)
                    .frame(minWidth: 480.0, minHeight: 480.0)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $isShowingWelcome) {
                importManager.loadInterruptedJobs()
            } content: {
                WelcomeView {
                    lastWelcomedVersion = welcomeVersion
                    isShowingWelcome = false
                }
                .macSheetSizing()
            }
    }

    private func handle(_ url: URL) {
        if url.pathExtension == "pics" {
            backupFile = BackupFile(url: url)
            return
        }
        guard url.scheme == "picmate" else { return }
        switch url.host {
        case "album":
            if let destination = DeepLinkRouter.albumDestination(
                from: url, currentLibraryID: libraryManager.currentLibrary.id
            ) {
                IntentNavigator.shared.open(destination)
            }
        case "internals":
            isShowingInternals = true
        case "entrophyrocks":
            generateSampleData(from: url)
        case "reonboard":
            presentWelcome()
        default:
            break
        }
    }

    private func openPendingIntentDestination() {
        guard libraryManager.hasLoadedLibraries,
              let destination = IntentNavigator.shared.pendingDestination else { return }
        IntentNavigator.shared.pendingDestination = nil
        Task {
            await DeepLinkRouter.open(destination, navigation: navigation, libraryManager: libraryManager)
        }
    }

    private func generateSampleData(from url: URL) {
        let (picCount, albumCount, legacyBlobs) = DeepLinkRouter.sampleDataCounts(from: url)
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

    private func promptForReviewIfNeeded() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !isShowingWelcome, libraryManager.hasLoadedLibraries, ViewerManager.picOpenCount >= 6,
              currentVersion != lastVersionPromptedForReview else { return }
        lastVersionPromptedForReview = currentVersion
        requestReview()
    }

    private func presentWelcomeIfNeeded() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard WelcomeView.shouldShow(currentVersion: currentVersion,
                                     lastSeenVersion: lastWelcomedVersion) else { return }
        presentWelcome()
    }

    private func presentWelcome() {
        welcomeVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        isShowingWelcome = true
    }
}

struct BackupFile: Identifiable {
    let url: URL
    var id: URL { url }
}
