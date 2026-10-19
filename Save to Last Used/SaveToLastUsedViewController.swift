import Engine
import SwiftUI

@objc(SaveToLastUsedViewController)
final class SaveToLastUsedViewController: SaveExtensionViewController {
    override func rootView(for session: SaveSession) -> AnyView {
        AnyView(LastUsedSaveView(session: session))
    }
}
