import AppKit
import SwiftUI

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {

    private static var openControllers: [ViewerWindowController] = []

    static func open(_ value: ViewerWindowValue) {
        guard let model = (NSApp.delegate as? AppDelegate)?.model else { return }
        let controller = ViewerWindowController(value: value, model: model)
        if let previous = openControllers.last?.window, let window = controller.window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: previous.frame.origin
                .applying(CGAffineTransform(translationX: 0.0, y: previous.frame.height))))
        } else {
            controller.window?.center()
        }
        openControllers.append(controller)
        controller.showWindow(nil)
    }

    private init(value: ViewerWindowValue, model: AppModel) {
        let hostingController = NSHostingController(rootView: ViewerWindowContent(value: value).environment(model))
        hostingController.sceneBridgingOptions = [.toolbars]
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 960.0, height: 720.0))
        window.contentMinSize = NSSize(width: 480.0, height: 360.0)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}
