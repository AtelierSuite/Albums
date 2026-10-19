import Engine
import SwiftUI

struct LibrariesView: View {

    enum Location {
        case onMyDevice
        case iCloud
    }

    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ConcurrencyManager.self) var concurrency
    @Environment(ImageMigrationManager.self) var imageMigration
    @Environment(PhotosManager.self) var photosManager

    @AppStorage("PhotosModeEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false
    @AppStorage("Libraries.Expanded.OnMyDevice", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isOnMyDeviceExpanded: Bool = true
    @AppStorage("Libraries.Expanded.iCloud", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isICloudExpanded: Bool = true
    @AppStorage("Libraries.Expanded.Photos", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosExpanded: Bool = true

    @State var isSettingsPresented: Bool = false
    @State var newLibraryLocation: Location?
    @State var newLibraryName: String = ""
    @State var libraryToEdit: PicLibrary?
    @State var libraryForCoverPicker: PicLibrary?
    @State var isEditingPhotos: Bool = false
    @State var isShowingICloudAlert: Bool = false
    @Namespace var sheetNamespace

    private let coverLength: CGFloat = 44.0

    var onMyDeviceLibraries: [PicLibrary] {
        libraryManager.libraries.filter { !$0.syncEnabled }
    }

    var iCloudLibraries: [PicLibrary] {
        libraryManager.libraries.filter(\.syncEnabled)
    }

    var body: some View {
        List {
            Section(isExpanded: $isOnMyDeviceExpanded) {
                ForEach(onMyDeviceLibraries) { library in
                    libraryRow(for: library)
                }
                addLibraryRow(in: .onMyDevice)
            } header: {
                Text("Libraries.Section.OnMyDevice", tableName: "Libraries")
            }
            Section(isExpanded: $isICloudExpanded) {
                ForEach(iCloudLibraries) { library in
                    libraryRow(for: library)
                }
                addLibraryRow(in: .iCloud)
            } header: {
                Text("Libraries.Section.iCloud", tableName: "Libraries")
            }
            Section(isExpanded: $isPhotosExpanded) {
                photosRow
            } header: {
                Text("Libraries.Section.Photos", tableName: "Libraries")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(String(localized: "Libraries.Title", table: "Libraries"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Label("ViewTitle.Settings", systemImage: "gearshape")
                }
                .matchedTransitionSource(id: "settings", in: sheetNamespace)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            MoreView()
                .phonePresentationDetents([.medium, .large])
                .navigationTransition(.zoom(sourceID: "settings", in: sheetNamespace))
        }
        .sheet(item: $libraryToEdit) { library in
            EditLibrarySheet(library: library, dismissAll: {
                libraryToEdit = nil
            })
            .environmentObject(libraryManager)
            .environmentObject(navigation)
            .environment(concurrency)
            .environment(imageMigration)
        }
        .sheet(item: $libraryForCoverPicker) { library in
            LibraryCoverPickerView(library: library) {
                Task { await LibraryCoverCache.shared.reload([library]) }
            }
        }
        .sheet(isPresented: $isEditingPhotos) {
            PhotosLibrarySheet()
        }
        .alert(String(localized: "Libraries.New", table: "Libraries"),
               isPresented: Binding(
                get: { newLibraryLocation != nil },
                set: { if !$0 { newLibraryLocation = nil } }
               )) {
            newLibraryAlertContent
        }
        .alert(Text("Sync.iCloudRequired.Title", tableName: "More"),
               isPresented: $isShowingICloudAlert) {
        } message: {
            Text("Sync.iCloudRequired.Message", tableName: "More")
        }
        .task(id: libraryManager.libraries) {
            await LibraryCoverCache.shared.reload(libraryManager.libraries)
        }
        .task(id: photosManager.authorizationStatus) {
            await LibraryCoverCache.shared.reloadPhotosLibrary(targetLength: coverLength * 3.0)
        }
        .onChange(of: navigation.dataVersion) { _, _ in
            Task { await LibraryCoverCache.shared.reload(libraryManager.libraries) }
        }
    }

    private func libraryRow(for library: PicLibrary) -> some View {
        let summary = LibraryCoverCache.shared.summary(for: library.id)
        return Button {
            open(library)
        } label: {
            rowLabel(title: libraryManager.displayName(for: library),
                     images: summary?.images ?? [],
                     placeholderSystemImage: "square.stack.3d.up.fill",
                     summary: summary)
        }
        .tint(.primary)
        .accessibilityIdentifier("library:\(library.id)")
        .contextMenu {
            Button(String(localized: "Libraries.Cover.Choose", table: "Libraries"),
                   systemImage: "photo.on.rectangle") {
                libraryForCoverPicker = library
            }
            Button(String(localized: "Libraries.Edit.Title", table: "Libraries"),
                   systemImage: "slider.horizontal.3") {
                libraryToEdit = library
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                libraryToEdit = library
            } label: {
                Label(String(localized: "Libraries.Edit.Title", table: "Libraries"),
                      systemImage: "slider.horizontal.3")
            }
            .tint(.accent)
        }
    }

    private var photosRow: some View {
        let summary = LibraryCoverCache.shared.summary(for: LibraryCoverCache.photosLibraryID)
        return Button {
            isPhotosModeEnabled = true
            navigation.collectionTabPath = [.photosLibrary]
        } label: {
            rowLabel(title: String(localized: "PhotosMode", table: "More"),
                     images: summary?.images ?? [],
                     placeholderSystemImage: "photo.on.rectangle.angled",
                     summary: summary)
        }
        .tint(.primary)
        .contextMenu {
            Button(String(localized: "Libraries.Edit.Title", table: "Libraries"),
                   systemImage: "slider.horizontal.3") {
                isEditingPhotos = true
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                isEditingPhotos = true
            } label: {
                Label(String(localized: "Libraries.Edit.Title", table: "Libraries"),
                      systemImage: "slider.horizontal.3")
            }
            .tint(.accent)
        }
    }

    private func rowLabel(title: String, images: [UIImage], placeholderSystemImage: String,
                          summary: LibraryCoverCache.Summary?) -> some View {
        HStack(spacing: 12.0) {
            LibraryCover(images: images, placeholderSystemImage: placeholderSystemImage,
                         length: coverLength)
            VStack(alignment: .leading, spacing: 4.0) {
                Text(title)
                    .lineLimit(1)
                if let summary {
                    AlbumItemCount(picCount: summary.picCount, albumCount: summary.albumCount)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0.0)
            Image(systemName: "chevron.forward")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2.0)
        .contentShape(.rect)
    }

    private func addLibraryRow(in location: Location) -> some View {
        Button {
            Task {
                if location == .iCloud, !(await SyncManager.shared.canEnableSync()) {
                    isShowingICloudAlert = true
                    return
                }
                newLibraryName = ""
                newLibraryLocation = location
            }
        } label: {
            HStack(spacing: 12.0) {
                Image(systemName: "plus")
                    .font(.title3)
                    .frame(width: coverLength, height: coverLength)
                Text("Libraries.New", tableName: "Libraries")
                Spacer(minLength: 0.0)
            }
            .foregroundStyle(.accent)
            .padding(.vertical, 2.0)
            .contentShape(.rect)
        }
        .tint(.accent)
    }

    @ViewBuilder
    private var newLibraryAlertContent: some View {
        TextField(String(localized: "Libraries.New.Placeholder", table: "Libraries"),
                  text: $newLibraryName)
        Button(String(localized: "Shared.Create", table: "Libraries")) {
            let name = newLibraryName
            let syncEnabled = newLibraryLocation == .iCloud
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Task {
                _ = await libraryManager.createLibrary(name: name, syncEnabled: syncEnabled)
            }
        }
        Button("Shared.Cancel", role: .cancel) { }
    }

    private func open(_ library: PicLibrary) {
        if library.id != libraryManager.currentLibrary.id || isPhotosModeEnabled {
            libraryManager.switchLibrary(to: library)
            navigation.signalDataChanged()
        }
        navigation.collectionTabPath = [.library(id: library.id)]
    }
}
