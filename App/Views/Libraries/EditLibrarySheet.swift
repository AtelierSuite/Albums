import Engine
import SwiftUI

// swiftlint:disable:next type_body_length
struct EditLibrarySheet: View {

    @Environment(\.dismiss) var dismiss
    @Environment(ConcurrencyManager.self) var concurrency
    @Environment(ImageMigrationManager.self) var imageMigration
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var navigation: NavigationManager

    @AppStorage("PhotosModeEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false

    var library: PicLibrary
    var dismissAll: (() -> Void)?

    @State var editedName: String = ""
    @State var picCount: Int = 0
    @State var albumCount: Int = 0

    @State var isPickingBackupFolder: Bool = false
    @State var isBackupSheetPresented: Bool = false
    @State var backupFolderURL: URL?
    @State var isDuplicateCheckerPresented: Bool = false

    @State var isConfirmingClearCache: Bool = false
    @State var migrationIncomplete: Bool = false

    @State var libraryToDelete: PicLibrary?
    @State var deleteConfirmationCode: String = ""
    @State var expectedDeleteCode: String = ""
    @State var isShowingActiveDeleteAlert: Bool = false

    @State var syncEnabled: Bool = false
    @State var iCloudAvailable: Bool = true
    @State var isShowingiCloudAlert: Bool = false
    @State var isConfirmingEnableSync: Bool = false
    @State var isConfirmingForceSync: Bool = false
    @State var isForceSyncing: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if UIDevice.current.userInterfaceIdiom != .phone,
                   library.id != libraryManager.currentLibrary.id || isPhotosModeEnabled {
                    Section {
                        Button(String(localized: "Libraries.SetActive", table: "Libraries")) {
                            withAnimation(.smooth.speed(2.0)) {
                                libraryManager.switchLibrary(to: library)
                                navigation.signalDataDeleted()
                            }
                        }
                    }
                }
                Section {
                    TextField(String(localized: "Libraries.New.Placeholder", table: "Libraries"),
                              text: $editedName)
                } header: {
                    Text("Libraries.Edit.Name", tableName: "Libraries")
                }
                Section {
                    Toggle(isOn: Binding(
                        get: { syncEnabled },
                        set: { newValue in
                            guard newValue else { return }
                            if !iCloudAvailable {
                                isShowingiCloudAlert = true
                                return
                            }
                            isConfirmingEnableSync = true
                        }
                    )) {
                        Text("Sync.Title", tableName: "More")
                    }
                    .disabled(migrationIncomplete || syncEnabled)
                    if syncEnabled {
                        Button {
                            isConfirmingForceSync = true
                        } label: {
                            HStack {
                                Text("Sync.Force.Title", tableName: "More")
                                if isForceSyncing {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isForceSyncing)
                    }
                } footer: {
                    Text("Sync.Footer", tableName: "More")
                }
                Section {
                    Button(String(localized: "DuplicateChecker", table: "More")) {
                        isDuplicateCheckerPresented = true
                    }
                    Button(String(localized: "Backup", table: "More")) {
                        isPickingBackupFolder = true
                    }
                } header: {
                    Text("Tools", tableName: "More")
                }
                Section {
                    if migrationIncomplete {
                        Button(String(localized: "Troubleshooting.Optimize", table: "More")) {
                            let libraryID = library.id
                            dismissAll?()
                            Task { await imageMigration.runIfNeeded(for: libraryID) }
                        }
                    }
                    Button(String(localized: "Troubleshooting.ClearCache", table: "More")) {
                        isConfirmingClearCache = true
                    }
                } header: {
                    Text("Troubleshooting.DataManagement", tableName: "More")
                }
                Section {
                    HStack(alignment: .top) {
                        VStack(spacing: 8.0) {
                            Text("\(picCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Shared.Pics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 8.0) {
                            Text("\(albumCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Shared.Albums")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        if UIDevice.current.userInterfaceIdiom != .phone,
                           library.id == libraryManager.currentLibrary.id {
                            isShowingActiveDeleteAlert = true
                            return
                        }
                        expectedDeleteCode = String(format: "%06d", Int.random(in: 0...999_999))
                        deleteConfirmationCode = ""
                        libraryToDelete = library
                    } label: {
                        Text("Libraries.Delete.Title", tableName: "Libraries")
                    }
                }
            }
            .tint(.accent)
            .navigationTitle(String(localized: "Libraries.Edit.Title", table: "Libraries"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && trimmed != library.name {
                            Task {
                                await libraryManager.renameLibrary(library, to: trimmed)
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
        .phonePresentationDetents([.medium, .large])
        .interactiveDismissDisabled()
        .onAppear {
            editedName = library.name
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task {
            await loadCounts()
            migrationIncomplete = await !DataActor.instance(for: library.id).isLibraryV2MigrationComplete()
            syncEnabled = await LibrariesActor.shared.isSyncEnabled(id: library.id)
            iCloudAvailable = await SyncManager.shared.canEnableSync()
        }
        .alert(Text("Sync.iCloudRequired.Title", tableName: "More"),
               isPresented: $isShowingiCloudAlert) {
        } message: {
            Text("Sync.iCloudRequired.Message", tableName: "More")
        }
        .alert(Text("Sync.EnableConfirm.Title", tableName: "More"),
               isPresented: $isConfirmingEnableSync) {
            Button("Shared.Yes") {
                syncEnabled = true
                Task {
                    await LibrariesActor.shared.setSyncEnabled(true, forID: library.id)
                    await libraryManager.reloadList()
                    await SyncManager.shared.refresh()
                }
            }
            Button("Shared.No", role: .cancel) { }
        } message: {
            Text("Sync.EnableConfirm.Message", tableName: "More")
        }
        .alert(Text("Sync.Force.Confirm.Title", tableName: "More"),
               isPresented: $isConfirmingForceSync) {
            Button("Shared.Yes") {
                isForceSyncing = true
                UIApplication.shared.isIdleTimerDisabled = true
                Task {
                    await SyncManager.shared.forcePush(forLibrary: library.id)
                    await MainActor.run {
                        isForceSyncing = false
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
            }
            Button("Shared.No", role: .cancel) { }
        } message: {
            Text("Sync.Force.Confirm.Message", tableName: "More")
        }
        .fileImporter(isPresented: $isPickingBackupFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                backupFolderURL = url
                isBackupSheetPresented = true
            case .failure(let error):
                debugPrint(error.localizedDescription)
            }
        }
        .sheet(isPresented: $isBackupSheetPresented) {
            if let backupFolderURL {
                MoreBackupView(destinationURL: backupFolderURL,
                              collectionID: library.id,
                              libraryName: libraryManager.displayName(for: library))
            }
        }
        .sheet(isPresented: $isDuplicateCheckerPresented) {
            DuplicateScanView(scanScope: .entireCollection, collectionID: library.id)
        }
        .alert(Text("Troubleshooting.ClearCache.Confirm.Title", tableName: "More"),
               isPresented: $isConfirmingClearCache) {
            Button("Shared.Yes", role: .destructive) {
                Task {
                    await HashActor.instance(for: library.id).deleteAllHashes()
                    await PColorActor.instance(for: library.id).deleteAllColors()
                    await CoverCacheActor.instance(for: library.id).deleteAllCovers()
                }
            }
            Button("Shared.No", role: .cancel) { }
        } message: {
            Text("Troubleshooting.ClearCache.Confirm.Message", tableName: "More")
        }
        .alert(String(localized: "Libraries.Delete.Title", table: "Libraries"),
               isPresented: Binding(
                get: { libraryToDelete != nil },
                set: { if !$0 { libraryToDelete = nil } }
               )) {
            TextField("", text: $deleteConfirmationCode, prompt: Text(expectedDeleteCode))
                .keyboardType(.numberPad)
            Button(String(localized: "Shared.Delete", table: "Libraries"), role: .destructive) {
                guard let library = libraryToDelete,
                      deleteConfirmationCode == expectedDeleteCode else { return }
                let wasCurrentLibrary = library.id == libraryManager.currentLibrary.id
                if wasCurrentLibrary {
                    libraryManager.switchLibrary(to: libraryManager.fallbackLibrary(excluding: library.id))
                }
                Task {
                    await libraryManager.deleteLibrary(library)
                    if wasCurrentLibrary {
                        navigation.signalDataDeleted()
                    }
                }
                libraryToDelete = nil
                dismiss()
            }
            .disabled(deleteConfirmationCode != expectedDeleteCode)
            Button("Shared.Cancel", role: .cancel) {
                libraryToDelete = nil
            }
        } message: {
            Text("Libraries.Delete.Message \(expectedDeleteCode)", tableName: "Libraries")
        }
        .alert(Text("Libraries.Delete.Active.Title", tableName: "Libraries"),
               isPresented: $isShowingActiveDeleteAlert) {
        } message: {
            Text("Libraries.Delete.Active.Message", tableName: "Libraries")
        }
    }

    func loadCounts() async {
        let dataActor = DataActor(collectionID: library.id)
        let albums = await dataActor.albumCount()
        let pics = await dataActor.picCount()
        await MainActor.run {
            albumCount = albums
            picCount = pics
        }
    }
}
