import Engine
import SwiftUI

@MainActor
enum MovedToast {
    static func showMoved(picIDs: [String], to destination: Album,
                          from fromAlbumID: String?, using dataActor: DataActor) {
        let destinationID = destination.id
        ToastManager.shared.show(ToastItem(
            message: String(localized: "Toast.MovedToAlbum.\(picIDs.count)-\(destination.name)",
                            table: "Photos"),
            undo: {
                if let fromAlbumID {
                    await dataActor.addPics(withIDs: picIDs, toAlbumWithID: fromAlbumID)
                    AlbumCoverCache.shared.removeImages(forAlbumID: fromAlbumID)
                } else {
                    await dataActor.removeParentAlbum(forPicsWithIDs: picIDs)
                }
                AlbumCoverCache.shared.removeImages(forAlbumID: destinationID)
            }))
    }
}
