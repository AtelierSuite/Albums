import Engine
import SwiftUI

struct PicMoveMenu: View {

    var title: LocalizedStringKey
    var systemImage: String
    var pics: [Pic]
    var containingAlbum: Album?
    var totalAlbumCount: Int
    var onMoved: () -> Void
    var onOtherLibraries: () -> Void

    @State var rootAlbums: [Album] = []
    @State var lastUsedAlbum: Album?

    var body: some View {
        Menu(title, systemImage: systemImage) {
            if let containingAlbum {
                Section {
                    Button("Shared.MoveOutOfAlbum", systemImage: "tray.and.arrow.up") {
                        moveOutOfAlbum(from: containingAlbum)
                    }
                }
            }
            if let lastUsedAlbum, lastUsedAlbum.id != containingAlbum?.id {
                Section {
                    Button(lastUsedAlbum.name, systemImage: "clock.arrow.circlepath") {
                        move(to: lastUsedAlbum)
                    }
                }
            }
            if !rootAlbums.isEmpty {
                Section {
                    ForEach(rootAlbums) { album in
                        AlbumHierarchyMenuItem(
                            targetAlbum: album,
                            excludingAlbumID: containingAlbum?.id ?? ""
                        ) { destinationAlbum in
                            move(to: destinationAlbum)
                        }
                    }
                }
            }
            Section {
                Button("Shared.MoveToOtherLibrary", systemImage: "square.stack.3d.up") {
                    onOtherLibraries()
                }
            }
        }
        .task {
            await loadAlbums()
        }
    }

    func move(to destinationAlbum: Album) {
        let dataActor = DataActor.shared
        let picIDs = pics.map { $0.id }
        let fromAlbumID = containingAlbum?.id
        let destinationID = destinationAlbum.id
        Task {
            await dataActor.addPics(withIDs: picIDs, toAlbumWithID: destinationID)
            if let fromAlbumID {
                AlbumCoverCache.shared.removeImages(forAlbumID: fromAlbumID)
            }
            AlbumCoverCache.shared.removeImages(forAlbumID: destinationID)
            LastUsedAlbum.set(destinationID, in: dataActor.collectionID)
            onMoved()
            MovedToast.showMoved(picIDs: picIDs, to: destinationAlbum,
                                 from: fromAlbumID, using: dataActor)
        }
    }

    func moveOutOfAlbum(from album: Album) {
        let dataActor = DataActor.shared
        let picIDs = pics.map { $0.id }
        let fromAlbumID = album.id
        Task {
            await dataActor.removeParentAlbum(forPicsWithIDs: picIDs)
            AlbumCoverCache.shared.removeImages(forAlbumID: fromAlbumID)
            onMoved()
            ToastManager.shared.show(ToastItem(
                message: String(localized: "Toast.MovedOutOfAlbum.\(picIDs.count)", table: "Photos"),
                undo: {
                    await dataActor.addPics(withIDs: picIDs, toAlbumWithID: fromAlbumID)
                    AlbumCoverCache.shared.removeImages(forAlbumID: fromAlbumID)
                }
            ))
        }
    }

    func loadAlbums() async {
        rootAlbums = (try? await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)) ?? []
        if let id = LastUsedAlbum.id(in: DataActor.shared.collectionID) {
            lastUsedAlbum = await DataActor.shared.album(for: id)
        } else {
            lastUsedAlbum = nil
        }
    }
}
