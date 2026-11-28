#if os(macOS)
import AppKit
import SwiftUI

extension ToolbarItemPlacement {
    public static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    public static var topBarLeading: ToolbarItemPlacement { .navigation }
    public static var bottomBar: ToolbarItemPlacement { .automatic }
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

extension ListStyle where Self == InsetListStyle {
    public static var insetGrouped: InsetListStyle { InsetListStyle() }
}

extension NSColor {
    public static var systemBackground: NSColor { .windowBackgroundColor }
    public static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    public static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    public static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    public static var secondarySystemFill: NSColor { .quaternaryLabelColor }
    public static var label: NSColor { .labelColor }
    public static var secondaryLabel: NSColor { .secondaryLabelColor }
}

extension Color {
    public init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

extension NSImage {
    public func preparingThumbnail(of size: CGSize) -> NSImage? {
        scalePreservingAspectRatio(targetSize: size)
    }
}
#endif
