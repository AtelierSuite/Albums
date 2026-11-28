import AppKit
import SwiftUI

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {

    private static var openControllers: [ViewerWindowController] = []
    fileprivate static let restorationKey = "ViewerWindowValue"
    fileprivate static let identifier = NSUserInterfaceItemIdentifier("ViewerWindow")

    private(set) var value: ViewerWindowValue

    static func open(_ value: ViewerWindowValue) {
        if let existing = openControllers.first(where: { $0.value.selectedID == value.selectedID }) {
            existing.showWindow(nil)
            return
        }
        guard let controller = make(value) else { return }
        if let previous = openControllers.dropLast().last?.window, let window = controller.window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: previous.frame.origin
                .applying(CGAffineTransform(translationX: 0.0, y: previous.frame.height))))
        } else {
            controller.window?.center()
        }
        controller.showWindow(nil)
    }

    fileprivate static func make(_ value: ViewerWindowValue) -> ViewerWindowController? {
        guard let model = (NSApp.delegate as? AppDelegate)?.model else { return nil }
        let controller = ViewerWindowController(value: value, model: model)
        openControllers.append(controller)
        return controller
    }

    private init(value: ViewerWindowValue, model: AppModel) {
        self.value = value
        let window = NSWindow(contentRect: NSRect(x: 0.0, y: 0.0, width: 960.0, height: 720.0),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        let content = ViewerWindowContent(value: value) { [weak self] id in
            self?.displayedIDChanged(to: id)
        }
        let hostingController = NSHostingController(rootView: content.appLockCover().environment(model))
        hostingController.sceneBridgingOptions = [.toolbars]
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 960.0, height: 720.0))
        window.contentMinSize = NSSize(width: 480.0, height: 360.0)
        window.isReleasedWhenClosed = false
        window.identifier = Self.identifier
        window.isRestorable = true
        window.restorationClass = ViewerWindowRestoration.self
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func displayedIDChanged(to id: String) {
        guard value.selectedID != id else { return }
        value = value.selecting(id)
        window?.invalidateRestorableState()
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        if let data = try? JSONEncoder().encode(value) {
            state.encode(data as NSData, forKey: Self.restorationKey)
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}

final class ViewerWindowRestoration: NSObject, NSWindowRestoration {

    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
                              completionHandler: @escaping (NSWindow?, (any Error)?) -> Void) {
        MainActor.assumeIsolated {
            guard identifier == ViewerWindowController.identifier,
                  let data = state.decodeObject(of: NSData.self, forKey: ViewerWindowController.restorationKey),
                  let value = try? JSONDecoder().decode(ViewerWindowValue.self, from: data as Data),
                  let controller = ViewerWindowController.make(value) else {
                completionHandler(nil, nil)
                return
            }
            completionHandler(controller.window, nil)
        }
    }
}

extension ViewerWindowValue {

    var selectedID: String {
        switch self {
        case .pic(let selectedID, _), .photo(let selectedID, _): selectedID
        }
    }

    func selecting(_ id: String) -> ViewerWindowValue {
        switch self {
        case .pic(_, let siblingIDs): .pic(selectedID: id, siblingIDs: siblingIDs)
        case .photo(_, let siblingIDs): .photo(selectedID: id, siblingIDs: siblingIDs)
        }
    }
}
