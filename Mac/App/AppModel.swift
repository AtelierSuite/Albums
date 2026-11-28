import Engine
import SwiftUI

@MainActor
final class AppModel {
    let navigation = NavigationManager()
    let libraryManager = LibraryManager()
    let viewer = ViewerManager()
    let concurrency = ConcurrencyManager()
    let photosManager = PhotosManager()
    let photosViewer = PhotosViewerManager()
    let auth = AuthenticationManager()
    let pipManager = PictureInPictureManager()
    let webServer = WebServerManager()
    let imageMigration = ImageMigrationManager()
    let importManager = ImportManager.shared
}

extension View {
    func environment(_ model: AppModel) -> some View {
        self
            .environment(model.importManager)
            .environmentObject(model.navigation)
            .environmentObject(model.libraryManager)
            .environment(model.viewer)
            .environment(model.concurrency)
            .environment(model.photosManager)
            .environment(model.photosViewer)
            .environment(model.auth)
            .environment(model.pipManager)
            .environment(model.webServer)
            .environment(model.imageMigration)
    }
}
