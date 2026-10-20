import Engine
import SwiftUI

let settingsWindowID = "settings"

struct MoreView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(AuthenticationManager.self) var auth
    @EnvironmentObject var navigation: NavigationManager

    @AppStorage("AppLockEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isAppLockEnabled: Bool = false
    @AppStorage(spotlightIndexingEnabledKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isSpotlightIndexingEnabled: Bool = true
    @AppStorage("ShareSheetOpenSearch", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var openSearchWhenSharing: Bool = false
    @AppStorage("ShareSheetShowAnimation", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var showAnimationWhenSaving: Bool = true
    @AppStorage("ShareSheetQuickImport",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var quickImport: Bool = false
    @AppStorage("ShareSheetDefaultAlbum",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var defaultAlbumID: String = ""
    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false
    @AppStorage(viewerFitToScreenKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var fitToScreen: Bool = false
    @AppStorage(viewerBackgroundTypeKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var viewerBackgroundType: ViewerBackgroundType = .immersive
    @AppStorage(viewerShowResolutionKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var showResolutionByDefault: Bool = true
    @AppStorage(importShowNotificationKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var showImportNotification: Bool = true

    @State var allAlbums: [Album] = []

    private var listContent: some View {
        List {
            Section {
                Toggle(String(localized: "AppLock", table: "More"), isOn: $isAppLockEnabled)
                    .disabled(auth.biometryType == .none)
            } header: {
                Text("Security", tableName: "More")
            } footer: {
                Text("AppLock.Description", tableName: "More")
            }
            Section {
                Toggle(String(localized: "Spotlight", table: "More"), isOn: $isSpotlightIndexingEnabled)
            } footer: {
                Text("Spotlight.Description", tableName: "More")
            }
            Section {
                Toggle(String(localized: "Viewer.FitToScreen", table: "More"), isOn: $fitToScreen)
                Picker(String(localized: "Viewer.BackgroundType", table: "More"),
                       selection: $viewerBackgroundType) {
                    Text("Viewer.BackgroundType.Immersive", tableName: "More")
                        .tag(ViewerBackgroundType.immersive)
                    Text("Viewer.BackgroundType.FollowSystem", tableName: "More")
                        .tag(ViewerBackgroundType.followSystem)
                    Text("Viewer.BackgroundType.Dark", tableName: "More")
                        .tag(ViewerBackgroundType.dark)
                }
                Toggle(String(localized: "Viewer.ShowResolution", table: "More"), isOn: $showResolutionByDefault)
                #if targetEnvironment(macCatalyst)
                Toggle(String(localized: "Window.OpenPicsInNewWindow", table: "More"), isOn: $openPicsInNewWindow)
                #endif
            } header: {
                Text("Viewer", tableName: "More")
            } footer: {
                #if targetEnvironment(macCatalyst)
                Text("Window.OpenPicsInNewWindow.Description", tableName: "More")
                #endif
            }
            Section {
                Toggle(String(localized: "ShareSheet.OpenSearch", table: "More"), isOn: $openSearchWhenSharing)
                Toggle(String(localized: "ShareSheet.ShowAnimation", table: "More"), isOn: $showAnimationWhenSaving)
                Toggle(String(localized: "ShareSheet.QuickImport", table: "More"), isOn: $quickImport)
                if quickImport {
                    Picker(String(localized: "ShareSheet.DefaultAlbum", table: "More"),
                           selection: $defaultAlbumID) {
                        Text("ShareSheet.DefaultAlbum.None", tableName: "More")
                            .tag("")
                        Divider()
                        Text("ShareSheet.DefaultAlbum.Collection", tableName: "More")
                            .tag("__collection__")
                        Divider()
                        ForEach(allAlbums) { album in
                            Text(album.name).tag(album.id)
                        }
                    }
                }
            } header: {
                Text("ShareSheet", tableName: "More")
            } footer: {
                if quickImport && !defaultAlbumID.isEmpty {
                    if defaultAlbumID == "__collection__" {
                        Text("ShareSheet.DefaultAlbum.Collection.Description", tableName: "More")
                    } else {
                        Text("ShareSheet.DefaultAlbum.Description", tableName: "More")
                    }
                } else {
                    Text("ShareSheet.QuickImport.Description", tableName: "More")
                }
            }
            Section {
                Toggle(String(localized: "Import.ShowNotification", table: "More"),
                       isOn: $showImportNotification)
            } header: {
                Text("Import", tableName: "More")
            } footer: {
                Text("Import.ShowNotification.Description", tableName: "More")
            }
            WebServerView()
            #if DEBUG
            Section {
                NavigationLink(String(localized: "Labs.FileExplorer", table: "More"),
                               value: ViewPath.moreLabsFileExplorer)
                NavigationLink(String(localized: "Labs.TestData", table: "More"),
                               value: ViewPath.moreLabsTestData)
            } header: {
                Text("Labs", tableName: "More")
            } footer: {
                Text("Labs.Description", tableName: "More")
            }
            #endif
            Section {
                Link(destination: URL(string: "https://github.com/Atelier/Albums")!) {
                    HStack {
                        Text(String(localized: "GitHub", table: "More"))
                        Spacer()
                        Text(verbatim: "Atelier/Albums")
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                NavigationLink(String(localized: "Attributions", table: "More"), value: ViewPath.moreAttributions)
            }
        }
        .tint(.accent)
#if targetEnvironment(macCatalyst)
        .navigationTitle("")
#else
        .navigationTitle("ViewTitle.More")
#endif
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ViewPath.self) { viewPath in
            switch viewPath {
            case .moreDebug: MoreExperimentsView()
            case .moreAttributions: MoreLicensesView()
            case .moreLabsFileExplorer: LabsFileExplorerView()
            case .moreLabsTestData: LabsTestDataView()
            default: Color.clear
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigation.moreTabPath) {
            listContent
                .toolbar {
#if !targetEnvironment(macCatalyst)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
#endif
                }
        }
        .task {
            await loadAlbums()
        }
        .onChange(of: navigation.dataVersion) { _, _ in
            dismiss()
        }
    }

    func loadAlbums() async {
        do {
            let albums = try await DataActor.shared.albumsWithCounts(sortedBy: .nameAscending)
            await MainActor.run {
                allAlbums = albums
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
    }
}
