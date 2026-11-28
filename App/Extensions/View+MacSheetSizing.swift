import SwiftUI

extension EnvironmentValues {
    @Entry var sheetContainerSize: CGSize = .zero
}

private struct FixedPresentationSizing: PresentationSizing {
    let size: CGSize

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(size)
    }
}

private struct SheetContainerSizeReader: ViewModifier {
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                       height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            } action: { newSize in
                size = newSize
            }
            .environment(\.sheetContainerSize, size)
    }
}

private struct MacSheetSizing: ViewModifier {
    @Environment(\.sheetContainerSize) private var containerSize

    private static let minimumSize = CGSize(width: 540.0, height: 620.0)
    private static let maximumSize = CGSize(width: 1400.0, height: 1200.0)
    private static let margin: CGFloat = 48.0

    func body(content: Content) -> some View {
        if containerSize.width > 0, containerSize.height > 0 {
            content.presentationSizing(FixedPresentationSizing(size: sheetSize))
        } else {
            content.presentationSizing(.page)
        }
    }

    private var sheetSize: CGSize {
        CGSize(width: dimension(containerSize.width, minimum: Self.minimumSize.width, maximum: Self.maximumSize.width),
               height: dimension(containerSize.height, minimum: Self.minimumSize.height,
                                 maximum: Self.maximumSize.height))
    }

    private func dimension(_ container: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let available = container - Self.margin * 2.0
        return min(max(min(available, maximum), minimum), container)
    }
}

extension View {
    @ViewBuilder
    func readsSheetContainerSize() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(SheetContainerSizeReader())
        #else
        self
        #endif
    }

    @ViewBuilder
    func macSheetSizing() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacSheetSizing())
        #else
        self
        #endif
    }
}
