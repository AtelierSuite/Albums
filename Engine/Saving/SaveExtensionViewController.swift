#if os(iOS)
import SwiftUI
import UIKit

@MainActor
open class SaveExtensionViewController: UIViewController {

    open func rootView(for session: SaveSession) -> AnyView {
        AnyView(EmptyView())
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Task { [weak self] in
            guard let self else { return }
            SharedItem.removeTemporaryCopies()
            let loaded = await SharedItem.load(from: extensionContext)
            let session = SaveSession(items: loaded.items, failedItemCount: loaded.failedCount) { [weak self] in
                SharedItem.removeTemporaryCopies()
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            spinner.removeFromSuperview()
            let host = UIHostingController(rootView: rootView(for: session))
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }
}
#elseif os(macOS)
import AppKit
import SwiftUI

@MainActor
open class SaveExtensionViewController: NSViewController {

    open func rootView(for session: SaveSession) -> AnyView {
        AnyView(EmptyView())
    }

    override open func loadView() {
        view = NSView(frame: NSRect(x: 0.0, y: 0.0, width: 480.0, height: 600.0))
        preferredContentSize = view.frame.size
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Task { [weak self] in
            guard let self else { return }
            SharedItem.removeTemporaryCopies()
            let loaded = await SharedItem.load(from: extensionContext)
            let session = SaveSession(items: loaded.items, failedItemCount: loaded.failedCount) { [weak self] in
                SharedItem.removeTemporaryCopies()
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            spinner.removeFromSuperview()
            let host = NSHostingController(rootView: rootView(for: session))
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.width, .height]
            view.addSubview(host.view)
        }
    }
}
#endif
