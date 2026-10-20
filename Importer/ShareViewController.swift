import Engine
import SwiftUI

final class ShareViewController: SaveExtensionViewController {

    override func viewDidLoad() {
        let libraryID = PicLibrary.persistedCurrentID
        DataActor.switchLibrary(to: libraryID)
        CoverCacheActor.switchLibrary(to: libraryID)
        super.viewDidLoad()
    }

    override func rootView(for session: SaveSession) -> AnyView {
        AnyView(ShareView(session: session))
    }
}
