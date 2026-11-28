import SwiftUI

struct AlbumMenuActions {
    var options: AlbumViewOptions
    var createAlbum: () -> Void
    var importPhotos: () -> Void
    var importVideos: () -> Void
    var browseAlbums: () -> Void
    var selectFolder: () -> Void
    var importFiles: () -> Void
}

@MainActor @Observable
final class MacMenuState {

    static let shared = MacMenuState()

    private(set) var album: AlbumMenuActions?
    @ObservationIgnored private var albumOwner: UUID?

    func activate(_ actions: AlbumMenuActions, owner: UUID) {
        album = actions
        albumOwner = owner
    }

    func deactivate(owner: UUID) {
        guard albumOwner == owner else { return }
        album = nil
        albumOwner = nil
    }
}

struct MacAlbumMenuModifier: ViewModifier {

    let actions: AlbumMenuActions

    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                MacMenuState.shared.activate(actions, owner: owner)
            }
            .onDisappear {
                MacMenuState.shared.deactivate(owner: owner)
            }
    }
}

enum ViewerNavigateCommand {
    case previous
    case next
}

extension Notification.Name {
    static let viewerNavigateCommand = Notification.Name("ViewerNavigateCommand")
}
