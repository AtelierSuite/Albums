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
