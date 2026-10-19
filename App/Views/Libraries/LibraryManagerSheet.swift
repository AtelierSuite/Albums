import Engine
import SwiftUI

struct LibraryManagerSheet: View {

    @Environment(\.dismiss) var dismiss
    @Environment(ConcurrencyManager.self) var concurrency
    @Environment(ImageMigrationManager.self) var imageMigration
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var navigation: NavigationManager

    @AppStorage("PhotosModeEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false

    @State var isCreatingLibrary: Bool = false
    @State var newLibraryName: String = ""
    @State var libraryToEdit: PicLibrary?
    @State var isEditingPhotos: Bool = false

    var body: some View {
        NavigationStack {
            libraryList
                .navigationTitle(String(localized: "Libraries.Title", table: "Libraries"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isCreatingLibrary = true
                            newLibraryName = ""
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .alert(String(localized: "Libraries.New", table: "Libraries"),
                       isPresented: $isCreatingLibrary) {
                    createLibraryAlertContent
                }
                .sheet(item: $libraryToEdit) { library in
                    EditLibrarySheet(library: library, dismissAll: {
                        libraryToEdit = nil
                        dismiss()
                    })
                        .environmentObject(libraryManager)
                        .environmentObject(navigation)
                        .environment(concurrency)
                        .environment(imageMigration)
                }
                .sheet(isPresented: $isEditingPhotos) {
                    PhotosLibrarySheet(dismissAll: {
                        isEditingPhotos = false
                        dismiss()
                    })
                }
        }
        .phonePresentationDetents([.medium, .large])
        .onChange(of: libraryManager.currentLibrary.id) { _, _ in
            dismiss()
        }
        .onChange(of: isPhotosModeEnabled) { _, _ in
            dismiss()
        }
    }

    private var libraryList: some View {
        List {
            Section {
                ForEach(libraryManager.libraries) { library in
                    libraryRow(for: library)
                }
            } header: {
                Text("Libraries.Section.PicMate", tableName: "Libraries")
            }
            Section {
                photosRow
            } header: {
                Text("Libraries.Section.Photos", tableName: "Libraries")
            } footer: {
                Text("PhotosMode.Description", tableName: "More")
            }
        }
    }

    private var photosRow: some View {
        Button {
            isEditingPhotos = true
        } label: {
            HStack {
                Text("PhotosMode", tableName: "More")
                Spacer()
                if isPhotosModeEnabled {
                    Text("Libraries.Active", tableName: "Libraries")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.accent, in: .capsule)
                }
            }
        }
        .tint(.primary)
    }

    private func libraryRow(for library: PicLibrary) -> some View {
        Button {
            libraryToEdit = library
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2.0) {
                    HStack(spacing: 4.0) {
                        Text(libraryManager.displayName(for: library))
                        if library.syncEnabled {
                            Image(systemName: "icloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("Sync.Title", tableName: "More"))
                        }
                    }
                    if library.isDefault {
                        Text("Libraries.Default.Description", tableName: "Libraries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if library.id == libraryManager.currentLibrary.id && !isPhotosModeEnabled {
                    Text("Libraries.Active", tableName: "Libraries")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.accent, in: .capsule)
                }
            }
        }
        .tint(.primary)
        .swipeActions(edge: .leading) {
            if library.id != libraryManager.currentLibrary.id || isPhotosModeEnabled {
                Button {
                    setLibraryActive(library)
                } label: {
                    Label(String(localized: "Libraries.SetActive.Short", table: "Libraries"),
                          systemImage: "checkmark.circle")
                }
                .tint(.accent)
            }
        }
    }

    private func setLibraryActive(_ library: PicLibrary) {
        libraryManager.switchLibrary(to: library)
        navigation.signalDataDeleted()
    }

    @ViewBuilder
    private var createLibraryAlertContent: some View {
        TextField(String(localized: "Libraries.New.Placeholder", table: "Libraries"),
                  text: $newLibraryName)
        Button(String(localized: "Shared.Create", table: "Libraries")) {
            guard !newLibraryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Task {
                _ = await libraryManager.createLibrary(name: newLibraryName)
            }
        }
        Button("Shared.Cancel", role: .cancel) { }
    }
}
