#if os(macOS)
import AppKit
import SwiftUI

extension ToolbarItemPlacement {
    public static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    public static var topBarLeading: ToolbarItemPlacement { .navigation }
    public static var bottomBar: ToolbarItemPlacement { .automatic }
    public static var subtitle: ToolbarItemPlacement { .automatic }
}

extension ToolbarPlacement {
    public static var bottomBar: ToolbarPlacement { .automatic }
}

public enum NavigationBarTitleDisplayMode: Sendable {
    case automatic
    case inline
    case large
}

public enum KeyboardType: Sendable {
    case `default`
    case numberPad
    case decimalPad
    case emailAddress
    case URL
}

public struct TextInputAutocapitalization: Sendable {
    public static let never = TextInputAutocapitalization()
    public static let words = TextInputAutocapitalization()
    public static let sentences = TextInputAutocapitalization()
    public static let characters = TextInputAutocapitalization()
}

extension View {
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarTitleDisplayMode) -> some View {
        self
    }

    public func keyboardType(_ type: KeyboardType) -> some View {
        self
    }

    public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }
}

extension MenuActionDismissBehavior {
    public static var disabled: MenuActionDismissBehavior { .automatic }
}

public enum ListSectionSpacing: Sendable {
    case `default`
    case compact
}

extension View {
    public func listSectionSpacing(_ spacing: ListSectionSpacing) -> some View {
        self
    }
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> AutomaticNavigationTransition {
        .automatic
    }
}

extension ListStyle where Self == InsetListStyle {
    public static var insetGrouped: InsetListStyle { InsetListStyle() }
    public static var grouped: InsetListStyle { InsetListStyle() }
}

extension NSColor {
    public static var systemBackground: NSColor { .windowBackgroundColor }
    public static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    public static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    public static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    public static var secondarySystemFill: NSColor { .quaternaryLabelColor }
    public static var systemGray5: NSColor { .quaternarySystemFill }
    public static var systemGray6: NSColor { .quinarySystemFill }
    public static var label: NSColor { .labelColor }
    public static var secondaryLabel: NSColor { .secondaryLabelColor }
}

extension Color {
    public init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

extension NSImage {
    public var scale: CGFloat {
        guard size.width > 0.0, let pixelsWide = representations.map(\.pixelsWide).max(), pixelsWide > 0 else {
            return 1.0
        }
        return CGFloat(pixelsWide) / size.width
    }

    public func preparingThumbnail(of size: CGSize) -> NSImage? {
        scalePreservingAspectRatio(targetSize: size)
    }
}
#endif
