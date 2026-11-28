import AppKit
import SwiftUI

struct WindowTitleUpdater: NSViewRepresentable {

    let title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}
