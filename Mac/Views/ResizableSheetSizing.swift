import AppKit
import SwiftUI

struct ResizableSheetSizing: ViewModifier {

    private static let minimumSize = CGSize(width: 520.0, height: 440.0)
    private static let defaultSize = CGSize(width: 760.0, height: 640.0)

    func body(content: Content) -> some View {
        content
            .frame(minWidth: Self.minimumSize.width, maxWidth: .infinity,
                   minHeight: Self.minimumSize.height, maxHeight: .infinity)
            .background {
                ResizableSheetWindowConfigurator(minimumSize: Self.minimumSize, defaultSize: Self.defaultSize)
            }
    }
}

private struct ResizableSheetWindowConfigurator: NSViewRepresentable {

    let minimumSize: CGSize
    let defaultSize: CGSize

    func makeNSView(context: Context) -> SheetWindowObservingView {
        SheetWindowObservingView(minimumSize: minimumSize, defaultSize: defaultSize)
    }

    func updateNSView(_ view: SheetWindowObservingView, context: Context) {}
}

final class SheetWindowObservingView: NSView {

    private let minimumSize: CGSize
    private let defaultSize: CGSize
    private var configuredWindow: NSWindow?

    init(minimumSize: CGSize, defaultSize: CGSize) {
        self.minimumSize = minimumSize
        self.defaultSize = defaultSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    private func configureWindow() {
        guard let window, window !== configuredWindow, window.sheetParent != nil else { return }
        configuredWindow = window
        window.styleMask.insert(.resizable)
        window.contentMinSize = minimumSize
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let parentSize = window.sheetParent?.contentLayoutRect.size ?? defaultSize
        let size = NSSize(width: min(defaultSize.width, max(parentSize.width - 80.0, minimumSize.width)),
                          height: min(defaultSize.height, max(parentSize.height - 60.0, minimumSize.height)))
        window.setContentSize(size)
    }
}
