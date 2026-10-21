import Photos
import SwiftUI

// MARK: - Sheets

extension PhotosCollectionView {
    @ViewBuilder
    var photosNewAlbumAlert: some View {
        TextField(String(localized: "Albums.Create.Placeholder", table: "Albums"), text: $newAlbumName)
            .textInputAutocapitalization(.words)
        Button("Shared.Create") {
            let name = newAlbumName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            Task {
                do {
                    _ = try await photosManager.createAlbum(named: name)
                    await MainActor.run {
                        newAlbumName = ""
                        refreshCollections()
                    }
                } catch {
                    debugPrint(error.localizedDescription)
                }
            }
        }
        Button("Shared.Cancel", role: .cancel) {
            newAlbumName = ""
        }
    }

    func photosRenameAlbumSheet(_ collection: PHAssetCollection) -> some View {
        NavigationStack {
            List {
                Section {
                    TextField(collection.localizedTitle ?? "", text: $renameText)
                        .textInputAutocapitalization(.words)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        do {
                            try await photosManager.renameAlbum(collection, to: renameText)
                            await MainActor.run {
                                albumToRename = nil
                                renameText = ""
                                refreshCollections()
                            }
                        } catch {
                            debugPrint(error.localizedDescription)
                        }
                    }
                } label: {
                    Text("Shared.Rename")
                        .bold()
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .buttonSizing(.flexible)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
                .padding(20.0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        albumToRename = nil
                        renameText = ""
                    }
                }
            }
            .navigationTitle("ViewTitle.Albums.Rename")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            renameText = collection.localizedTitle ?? ""
        }
        .phonePresentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    func photosMoveFolderSheet(_ collection: PHAssetCollection) -> some View {
        NavigationStack {
            PhotosFolderPickerView(album: collection) {
                albumToMove = nil
                refreshCollections()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        albumToMove = nil
                    }
                }
            }
            .navigationTitle(String(localized: "Photos.MoveToFolder", table: "Photos"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .phonePresentationDetents([.medium, .large])
    }
}
