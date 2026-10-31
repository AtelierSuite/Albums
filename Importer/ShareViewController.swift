import Engine
import SwiftUI

final class ShareViewController: SaveExtensionViewController {

    override func viewDidLoad() {
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        let usesDefaultAlbum = defaults?.bool(forKey: "ShareSheetQuickImport") == true
            && !(defaults?.string(forKey: "ShareSheetDefaultAlbum") ?? "").isEmpty
        let libraryID = usesDefaultAlbum
            ? PicLibrary.persistedCurrentID
            : defaults?.string(forKey: ShareView.lastLibraryKey) ?? PicLibrary.persistedCurrentID
        DataActor.switchLibrary(to: libraryID)
        CoverCacheActor.switchLibrary(to: libraryID)
        super.viewDidLoad()
    }

    override func rootView(for session: SaveSession) -> AnyView {
        AnyView(ShareView(session: session))
    }
}
