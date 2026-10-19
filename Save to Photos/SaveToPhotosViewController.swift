import Engine
import SwiftUI

@objc(SaveToPhotosViewController)
final class SaveToPhotosViewController: SaveExtensionViewController {
    override func rootView(for session: SaveSession) -> AnyView {
        AnyView(PhotosSaveView(session: session))
    }
}
