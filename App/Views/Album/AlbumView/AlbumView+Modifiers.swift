import Engine
import SwiftUI

struct AlbumViewSheets: ViewModifier {
    @Binding var isAddingAlbum: Bool
    @Binding var newAlbumName: String
    @Binding var albumToRename: Album?
    @Binding var renameAlbumText: String
    @Binding var isBrowsingAlbums: Bool
    @Binding var isBrowsingFolders: Bool
    @Binding var isImportingPhotos: Bool
    let currentAlbum: Album?
    let onAlbumDismiss: () -> Void
    let onBrowseAlbumsDismiss: () -> Void
    let onImportDismiss: () -> Void

    // swiftlint:disable:next function_body_length
    func body(content: Content) -> some View {
        content
            .alert("ViewTitle.Albums.Create", isPresented: $isAddingAlbum) {
                TextField(String(localized: "Albums.Create.Placeholder", table: "Albums"),
                          text: $newAlbumName)
                    .textInputAutocapitalization(.words)
                Button("Shared.Create") {
                    let name = newAlbumName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        let newAlbum = await DataActor.shared.createAlbum(name)
                        if let currentAlbum {
                            await DataActor.shared.addAlbum(withID: newAlbum.id,
                                                 toAlbumWithID: currentAlbum.id)
                            AlbumCoverCache.shared.removeImages(forAlbumID: currentAlbum.id)
                        }
                        await MainActor.run {
                            newAlbumName = ""
                            onAlbumDismiss()
                        }
                    }
                }
                Button("Shared.Cancel", role: .cancel) {
                    newAlbumName = ""
                }
            }
            .alert("ViewTitle.Albums.Rename", isPresented: Binding(
                get: { albumToRename != nil },
                set: { if !$0 { albumToRename = nil } }
            )) {
                TextField(String(localized: "Albums.Create.Placeholder", table: "Albums"),
                          text: $renameAlbumText)
                    .textInputAutocapitalization(.words)
                Button("Shared.Rename") {
                    let name = renameAlbumText.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, let album = albumToRename else { return }
                    Task {
                        await DataActor.shared.renameAlbum(withID: album.id, to: name)
                        await MainActor.run {
                            renameAlbumText = ""
                            albumToRename = nil
                            onAlbumDismiss()
                        }
                    }
                }
                Button("Shared.Cancel", role: .cancel) {
                    renameAlbumText = ""
                    albumToRename = nil
                }
            }
            .sheet(isPresented: $isBrowsingAlbums) {
                onBrowseAlbumsDismiss()
            } content: {
                NavigationStack {
                    PhotosAlbumPickerView(selectedAlbum: currentAlbum) {
                        isBrowsingAlbums = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .cancel) {
                                isBrowsingAlbums = false
                            }
                        }
                    }
                }
                .phonePresentationDetents([.large])
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $isBrowsingFolders) {
                onBrowseAlbumsDismiss()
            } content: {
                NavigationStack {
                    PhotosFolderImportPickerView(selectedAlbum: currentAlbum) {
                        isBrowsingFolders = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .cancel) {
                                isBrowsingFolders = false
                            }
                        }
                    }
                }
                .phonePresentationDetents([.large])
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $isImportingPhotos) {
                onImportDismiss()
            } content: {
                ImportProgressView()
            }
    }
}

struct AlbumViewDialogs: ViewModifier {
    @Binding var isConfirmingDeleteAlbum: Bool
    @Binding var isConfirmingDeletePic: Bool
    @Binding var isConfirmingDeleteSelectedPics: Bool
    @Binding var albumPendingDeletion: Album?
    @Binding var picPendingDeletion: Pic?
    let selectedPicsCount: Int
    let onConfirmDeleteAlbum: (Bool) -> Void
    let onConfirmDeletePic: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Shared.DeleteConfirmation.Album.\(albumPendingDeletion?.name ?? "")"),
                isPresented: $isConfirmingDeleteAlbum
            ) {
                Button("Shared.DeleteConfirmation.Album.DeleteOnly", role: .destructive) {
                    onConfirmDeleteAlbum(false)
                }
                Button("Shared.DeleteConfirmation.Album.DeleteContents", role: .destructive) {
                    onConfirmDeleteAlbum(true)
                }
                Button("Shared.Cancel", role: .cancel) {
                    albumPendingDeletion = nil
                }
            } message: {
                Text("Shared.DeleteConfirmation.Album.Message")
            }
            .alert("Shared.DeleteConfirmation.Pic",
                   isPresented: $isConfirmingDeletePic) {
                Button("Shared.Yes", role: .destructive) {
                    onConfirmDeletePic()
                }
                Button("Shared.No", role: .cancel) {
                    picPendingDeletion = nil
                }
            }
            .alert("Shared.DeleteConfirmation.Pic.\(selectedPicsCount)",
                   isPresented: $isConfirmingDeleteSelectedPics) {
                Button("Shared.Yes", role: .destructive) {
                    onConfirmDeletePic()
                }
                Button("Shared.No", role: .cancel) {
                    picPendingDeletion = nil
                }
            }
    }
}
