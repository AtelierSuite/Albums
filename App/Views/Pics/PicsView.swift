import Engine
import SwiftUI

struct PicsView: View {

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var navigation: NavigationManager
    @Environment(ViewerManager.self) var viewer

    @AppStorage(openPicsInNewWindowKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var openPicsInNewWindow: Bool = false
    @AppStorage(picViewStyleKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var picViewStyle: ViewStyle = .grid

    @Namespace var namespace

    @State var pics: [Pic] = []
    @State var picToRename: Pic?
    @State var viewerManager = ViewerManager()

    var body: some View {
        ZStack {
            NavigationStack(path: $navigation.picsTabPath) {
                ScrollView(.vertical) {
                    PicsGrid(namespace: namespace,
                             pics: pics,
                             isSelecting: .constant(false),
                             enableSelection: false,
                             style: picViewStyle) { pic in
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            viewer.setDisplay(pic, in: pics) { [navigation] in
                                navigation.push(.picViewer(namespace: namespace), for: .pics)
                            }
                        } else {
#if targetEnvironment(macCatalyst)
                            if openPicsInNewWindow {
                                openWindow(value: ViewerWindowValue.pic(
                                    selectedID: pic.id, siblingIDs: pics.map(\.id)))
                            } else {
                                viewer.setDisplay(pic, in: pics) { }
                            }
#else
                            viewer.setDisplay(pic, in: pics) { }
#endif
                        }
                    } selectedCount: {
                        return 0
                    } onRename: { pic in
                        picToRename = pic
                    } moveMenu: { _ in
                        // TODO: Move menu support in macOS Pics view
                    }
                }
                .toolbar {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(alignment: .center, spacing: 8.0) {
                                Text("\(pics.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("ViewTitle.Pics")
            }
            .onAppear {
                refreshPics()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    refreshPics()
                }
            }
            .onChange(of: navigation.dataVersion) { _, _ in
                refreshPics()
            }
            .sheet(item: $picToRename) {
                refreshPics()
            } content: { pic in
                RenamePicView(pic: pic)
            }
        }
    }

    func refreshPics() {
        Task.detached(priority: .userInitiated) {
            do {
                let pics = try await DataActor.shared.pics()
                await MainActor.run {
                    doWithAnimation {
                        self.pics = pics
                    }
                }
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
