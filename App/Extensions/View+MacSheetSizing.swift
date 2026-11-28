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
    @AppStorage("MacSheetWidth") private var storedWidth: Double = 0.0
    @AppStorage("MacSheetHeight") private var storedHeight: Double = 0.0
    @State private var dragCornerOffset: CGSize?

    private static let defaultMinimumSize = CGSize(width: 540.0, height: 620.0)
    private static let resizeMinimumSize = CGSize(width: 420.0, height: 360.0)
    private static let maximumSize = CGSize(width: 1400.0, height: 1200.0)
    private static let margin: CGFloat = 48.0
    private static let resizeMargin: CGFloat = 12.0
    private static let coordinateSpaceName = "MacSheet"

    func body(content: Content) -> some View {
        if containerSize.width > 0, containerSize.height > 0 {
            content
                .overlay(alignment: .bottomTrailing) {
                    resizeGrip
                }
                .background {
                    PresentedSheetSizeApplier(size: sheetSize)
                }
                .coordinateSpace(.named(Self.coordinateSpaceName))
                .presentationSizing(FixedPresentationSizing(size: sheetSize))
        } else {
            content.presentationSizing(.page)
        }
    }

    private var resizeGrip: some View {
        SheetResizeGrip()
            .frame(width: 36.0, height: 36.0)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 1.0, coordinateSpace: .named(Self.coordinateSpaceName))
                    .onChanged { value in
                        let current = sheetSize
                        let offset = dragCornerOffset ?? CGSize(width: current.width - value.startLocation.x,
                                                                height: current.height - value.startLocation.y)
                        dragCornerOffset = offset
                        // The sheet stays centered and this space moves with it, so solve for the size whose corner meets the pointer.
                        let resized = clampedToContainer(
                            CGSize(width: (value.location.x + offset.width) * 2.0 - current.width,
                                   height: (value.location.y + offset.height) * 2.0 - current.height)
                        )
                        storedWidth = resized.width
                        storedHeight = resized.height
                    }
                    .onEnded { _ in
                        dragCornerOffset = nil
                    }
            )
            .onTapGesture(count: 2) {
                storedWidth = 0.0
                storedHeight = 0.0
            }
            .ignoresSafeArea()
    }

    private var sheetSize: CGSize {
        if storedWidth > 0.0, storedHeight > 0.0 {
            return clampedToContainer(CGSize(width: storedWidth, height: storedHeight))
        }
        return CGSize(width: defaultDimension(containerSize.width,
                                              minimum: Self.defaultMinimumSize.width,
                                              maximum: Self.maximumSize.width),
                      height: defaultDimension(containerSize.height,
                                               minimum: Self.defaultMinimumSize.height,
                                               maximum: Self.maximumSize.height))
    }

    private func defaultDimension(_ container: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let available = container - Self.margin * 2.0
        return min(max(min(available, maximum), minimum), container)
    }

    private func clampedToContainer(_ size: CGSize) -> CGSize {
        let maxWidth = max(containerSize.width - Self.resizeMargin * 2.0, Self.resizeMinimumSize.width)
        let maxHeight = max(containerSize.height - Self.resizeMargin * 2.0, Self.resizeMinimumSize.height)
        return CGSize(width: min(max(size.width, Self.resizeMinimumSize.width), maxWidth),
                      height: min(max(size.height, Self.resizeMinimumSize.height), maxHeight))
    }
}

private struct SheetResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for inset in stride(from: 6.0, through: 14.0, by: 4.0) {
                path.move(to: CGPoint(x: size.width - 5.0, y: size.height - 5.0 - inset))
                path.addLine(to: CGPoint(x: size.width - 5.0 - inset, y: size.height - 5.0))
            }
            context.stroke(path, with: .style(.secondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .accessibilityHidden(true)
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

private struct PresentedSheetSizeApplier: UIViewRepresentable {
    let size: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let size = size
        DispatchQueue.main.async {
            var responder: UIResponder? = uiView
            while let current = responder {
                if let controller = current as? UIViewController, controller.presentingViewController != nil,
                   controller.parent == nil {
                    // Catalyst ignores presentationSizing changes while the sheet is on screen.
                    guard controller.preferredContentSize != size else { return }
                    controller.preferredContentSize = size
                    controller.presentationController?.containerView?.setNeedsLayout()
                    controller.presentationController?.containerView?.layoutIfNeeded()
                    return
                }
                responder = current.next
            }
        }
    }
}
