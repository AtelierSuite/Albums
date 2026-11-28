import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {

    init(model: AppModel) {
        let hostingController = NSHostingController(rootView: SettingsView().environment(model))
        hostingController.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600.0, height: 640.0))
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
