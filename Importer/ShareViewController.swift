import Engine
import SwiftUI

final class ShareViewController: SaveExtensionViewController {

    override func viewDidLoad() {
        let store = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        let libraryID = store?.string(forKey: "CurrentCollectionID") ?? PicLibrary.defaultID
        DataActor.switchLibrary(to: libraryID)
        CoverCacheActor.switchLibrary(to: libraryID)
        super.viewDidLoad()
    }

    override func rootView(for session: SaveSession) -> AnyView {
        AnyView(ShareView(session: session))
    }
}
