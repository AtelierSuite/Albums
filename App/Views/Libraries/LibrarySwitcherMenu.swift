import SwiftUI
import TipKit

struct LibrarySwitcherMenu: View {

    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var navigation: NavigationManager

    @AppStorage("PhotosModeEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false

    @Binding var isLibraryManagerPresented: Bool

    var body: some View {
        Menu {
            Section(String(localized: "Libraries.Section.PicMate", table: "Libraries")) {
                ForEach(libraryManager.libraries) { library in
                    Button {
                        guard library.id != libraryManager.currentLibrary.id
                                || isPhotosModeEnabled else { return }
                        libraryManager.switchLibrary(to: library)
                        navigation.signalDataDeleted()
                    } label: {
                        if library.id == libraryManager.currentLibrary.id && !isPhotosModeEnabled {
                            Label(libraryManager.displayName(for: library),
                                  systemImage: "checkmark")
                        } else {
                            Text(libraryManager.displayName(for: library))
                        }
                    }
                }
                Button {
                    isLibraryManagerPresented = true
                } label: {
                    Label(String(localized: "Libraries.Manage", table: "Libraries"),
                          systemImage: "slider.horizontal.3")
                }
            }
            Section(String(localized: "Libraries.Section.Photos", table: "Libraries")) {
                Button {
                    isPhotosModeEnabled = true
                } label: {
                    if isPhotosModeEnabled {
                        Label(String(localized: "PhotosMode", table: "More"),
                              systemImage: "checkmark")
                    } else {
                        Text("PhotosMode", tableName: "More")
                    }
                }
            }
        } label: {
            if isPhotosModeEnabled {
                Label(String(localized: "PhotosMode", table: "More"),
                      systemImage: "square.stack.3d.up")
            } else {
                Label(libraryManager.displayName(for: libraryManager.currentLibrary),
                      systemImage: "square.stack.3d.up")
            }
        }
        #if os(macOS)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        #endif
        .popoverTip(LibrariesTip(), arrowEdge: .top)
    }
}
