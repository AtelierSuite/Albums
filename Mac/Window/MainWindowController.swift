import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {

    init(model: AppModel) {
        let hostingController = NSHostingController(rootView: MacRootView().environment(model))
        hostingController.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1100.0, height: 720.0))
        window.contentMinSize = NSSize(width: 720.0, height: 480.0)
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
