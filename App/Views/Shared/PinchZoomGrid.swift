import SwiftUI
import UIKit

struct PinchZoomGrid<Content: View, Preview: View>: View {

    var columnCount: Int
    var itemCount: Int
    var range: ClosedRange<Int> = 2...10
    var spacing: CGFloat = 2.0
    var onColumnCountChange: ((Int) -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var preview: (Int, Int) -> Preview

    private static var coordinateSpace: String { "PinchZoomGridSpace" }

    @State private var zoom = PinchZoomState()
    @State private var gridWidth: CGFloat = 0.0

    var body: some View {
        content()
            .opacity(zoom.session == nil ? 1.0 : 0.0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                gridWidth = width
            }
            .overlay(alignment: .topLeading) {
                PinchZoomOverlay(zoom: zoom, preview: preview)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.coordinateSpace))
            .gesture(PinchZoomGesture(isEnabled: onColumnCountChange != nil && !zoom.isSettling,
                                      coordinateSpace: Self.coordinateSpace,
                                      onBegan: { begin(at: $0, viewport: $1) },
                                      onChanged: { update(scale: $0, location: $1) },
                                      onEnded: { end(velocity: $0, scroller: $1) }))
    }

    private func begin(at location: CGPoint, viewport: CGRect) {
        guard gridWidth > 0.0, itemCount > 0, !zoom.isSettling else { return }
        let start = columnCount
        let cellWidth = PinchZoomSession.cellWidth(columns: CGFloat(start), width: gridWidth, spacing: spacing)
        let pitch = cellWidth + spacing
        let row = max(Int(location.y / pitch), 0)
        let column = min(max(Int(location.x / pitch), 0), start - 1)
        let fraction = min(max((location.y - CGFloat(row) * pitch) / cellWidth, 0.0), 1.0)
        zoom.session = PinchZoomSession(startCount: start,
                                        lower: min(range.lowerBound, start),
                                        upper: max(range.upperBound, start),
                                        width: gridWidth,
                                        spacing: spacing,
                                        itemCount: itemCount,
                                        viewport: viewport,
                                        anchorIndex: row * start + column,
                                        anchorFraction: fraction)
        zoom.progress = CGFloat(start)
        zoom.focusY = location.y
    }

    private func update(scale: CGFloat, location: CGPoint) {
        guard let session = zoom.session, !zoom.isSettling else { return }
        let startWidth = session.cellWidth(columns: CGFloat(session.startCount))
        let columns = session.columns(forCellWidth: startWidth * max(scale, 0.01))
        zoom.progress = session.rubberBanded(columns)
        zoom.focusY = location.y
    }

    private func end(velocity: CGFloat, scroller: PinchZoomScroller) {
        guard let session = zoom.session, !zoom.isSettling else { return }
        let progress = zoom.progress
        var target: Int
        if velocity > 0.5 {
            target = Int(progress.rounded(.down))
        } else if velocity < -0.5 {
            target = Int(progress.rounded(.up))
        } else {
            target = Int(progress.rounded())
        }
        target = min(max(target, session.lower), session.upper)

        let anchorY = session.anchorY(columns: target)
        let heightChange = session.gridHeight(columns: target) - session.gridHeight(columns: session.startCount)
        let scrollDelta = scroller.clampedDelta(anchorY - zoom.focusY, contentHeightChange: heightChange)

        zoom.isSettling = true
        withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
            zoom.progress = CGFloat(target)
            zoom.focusY = anchorY - scrollDelta
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if target != session.startCount {
                    onColumnCountChange?(target)
                }
                scroller.scroll(by: scrollDelta)
                zoom.session = nil
                zoom.isSettling = false
            }
        }
    }
}

@Observable
@MainActor
final class PinchZoomState {
    var session: PinchZoomSession?
    var progress: CGFloat = 0.0
    var focusY: CGFloat = 0.0
    var isSettling = false
}

struct PinchZoomSession {
    var startCount: Int
    var lower: Int
    var upper: Int
    var width: CGFloat
    var spacing: CGFloat
    var itemCount: Int
    var viewport: CGRect
    var anchorIndex: Int
    var anchorFraction: CGFloat

    static func cellWidth(columns: CGFloat, width: CGFloat, spacing: CGFloat) -> CGFloat {
        max((width - spacing * (columns - 1.0)) / columns, 1.0)
    }

    func cellWidth(columns: CGFloat) -> CGFloat {
        Self.cellWidth(columns: columns, width: width, spacing: spacing)
    }

    func columns(forCellWidth cellWidth: CGFloat) -> CGFloat {
        (width + spacing) / (cellWidth + spacing)
    }

    func rubberBanded(_ columns: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(lower)
        let upperBound = CGFloat(upper)
        if columns < lowerBound {
            let excess = lowerBound - columns
            return lowerBound - excess / (1.0 + excess * 2.0)
        } else if columns > upperBound {
            let excess = columns - upperBound
            return upperBound + excess / (1.0 + excess * 2.0)
        }
        return columns
    }

    func anchorY(columns: Int) -> CGFloat {
        let cellWidth = cellWidth(columns: CGFloat(columns))
        return CGFloat(anchorIndex / columns) * (cellWidth + spacing) + anchorFraction * cellWidth
    }

    func gridHeight(columns: Int) -> CGFloat {
        guard itemCount > 0 else { return 0.0 }
        let rows = (itemCount + columns - 1) / columns
        return CGFloat(rows) * cellWidth(columns: CGFloat(columns)) + CGFloat(rows - 1) * spacing
    }

    func morph(progress: CGFloat) -> PinchZoomMorph {
        let fewer = min(max(Int(progress.rounded(.down)), lower), upper)
        let more = min(fewer + 1, upper)
        let fraction = more == fewer ? 0.0 : min(max((progress - CGFloat(fewer)) / 0.3, 0.0), 1.0)
        let cellWidth = cellWidth(columns: progress)
        return PinchZoomMorph(fewerColumns: fewer,
                              moreColumns: more,
                              blend: fraction * fraction * (3.0 - 2.0 * fraction),
                              cellWidth: cellWidth,
                              pitch: cellWidth + spacing)
    }

    func cellOrigin(index: Int, columns: Int, morph: PinchZoomMorph, focusY: CGFloat) -> CGPoint {
        let anchorTop = focusY - anchorFraction * morph.cellWidth
        return CGPoint(x: CGFloat(index % columns) * morph.pitch,
                       y: anchorTop + CGFloat(index / columns - anchorIndex / columns) * morph.pitch)
    }

    func visibleItems(columns: Int, morph: PinchZoomMorph, focusY: CGFloat) -> Range<Int> {
        let anchorTop = focusY - anchorFraction * morph.cellWidth
        let anchorRow = anchorIndex / columns
        let firstRow = max(anchorRow + Int(((viewport.minY - anchorTop) / morph.pitch).rounded(.down)), 0)
        let lastRow = anchorRow + Int(((viewport.maxY - anchorTop) / morph.pitch).rounded(.down))
        let first = min(firstRow * columns, itemCount)
        let last = min(max((lastRow + 1) * columns, first), itemCount)
        return first..<last
    }
}

struct PinchZoomMorph {
    var fewerColumns: Int
    var moreColumns: Int
    var blend: CGFloat
    var cellWidth: CGFloat
    var pitch: CGFloat
}

private struct PinchZoomOverlay<Preview: View>: View {

    var zoom: PinchZoomState
    var preview: (Int, Int) -> Preview

    var body: some View {
        if let session = zoom.session {
            PinchZoomLayers(session: session,
                            progress: zoom.progress,
                            focusY: zoom.focusY,
                            preview: preview)
        }
    }
}

@Animatable
private struct PinchZoomLayers<Preview: View>: View {

    @AnimatableIgnored var session: PinchZoomSession
    var progress: CGFloat
    var focusY: CGFloat
    @AnimatableIgnored var preview: (Int, Int) -> Preview

    var body: some View {
        let morph = session.morph(progress: progress)
        let fromItems = session.visibleItems(columns: morph.fewerColumns, morph: morph, focusY: focusY)
        let toItems = session.visibleItems(columns: morph.moreColumns, morph: morph, focusY: focusY)
        let items = min(fromItems.lowerBound, toItems.lowerBound)..<max(fromItems.upperBound, toItems.upperBound)
        let columns = morph.blend < 0.5 ? morph.fewerColumns : morph.moreColumns
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { index in
                let start = session.cellOrigin(index: index, columns: morph.fewerColumns, morph: morph, focusY: focusY)
                let end = session.cellOrigin(index: index, columns: morph.moreColumns, morph: morph, focusY: focusY)
                if abs(end.x - start.x) > morph.pitch * 1.5 {
                    cell(index, columns: columns, size: morph.cellWidth, at: start)
                        .opacity(1.0 - morph.blend)
                    cell(index, columns: columns, size: morph.cellWidth, at: end)
                        .opacity(morph.blend)
                } else {
                    cell(index, columns: columns, size: morph.cellWidth,
                         at: CGPoint(x: start.x + (end.x - start.x) * morph.blend,
                                     y: start.y + (end.y - start.y) * morph.blend))
                }
            }
        }
        .frame(width: session.width, alignment: .topLeading)
    }

    private func cell(_ index: Int, columns: Int, size: CGFloat, at origin: CGPoint) -> some View {
        preview(index, columns)
            .frame(width: size, height: size)
            .offset(x: origin.x, y: origin.y)
    }
}

@MainActor
struct PinchZoomScroller {

    weak var scrollView: UIScrollView?

    func clampedDelta(_ delta: CGFloat, contentHeightChange: CGFloat) -> CGFloat {
        guard let scrollView else { return 0.0 }
        let inset = scrollView.adjustedContentInset
        let minimum = -inset.top
        let maximum = max(minimum, scrollView.contentSize.height + contentHeightChange
                          + inset.bottom - scrollView.bounds.height)
        let current = scrollView.contentOffset.y
        return min(max(current + delta, minimum), maximum) - current
    }

    func scroll(by delta: CGFloat) {
        guard let scrollView, delta != 0.0 else { return }
        scrollView.contentOffset.y += delta
    }
}

struct PinchZoomGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool
    var coordinateSpace: String
    var onBegan: (CGPoint, CGRect) -> Void
    var onChanged: (CGFloat, CGPoint) -> Void
    var onEnded: (CGFloat, PinchZoomScroller) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            coordinator.engaged = true
            coordinator.startScale = max(recognizer.scale, 0.01)
            let location = context.converter.location(in: .named(coordinateSpace))
            var viewport = CGRect(x: 0.0, y: location.y - 1000.0, width: 0.0, height: 2000.0)
            if let scrollView = coordinator.enclosingScrollView(of: recognizer.view) {
                coordinator.scrollView = scrollView
                scrollView.isScrollEnabled = false
                let locationInScrollView = recognizer.location(in: scrollView)
                viewport = scrollView.bounds.offsetBy(dx: location.x - locationInScrollView.x,
                                                      dy: location.y - locationInScrollView.y)
            }
            onBegan(location, viewport)
        case .changed:
            guard coordinator.engaged else { return }
            onChanged(recognizer.scale / coordinator.startScale,
                      context.converter.location(in: .named(coordinateSpace)))
        case .ended, .cancelled, .failed:
            guard coordinator.engaged else { return }
            coordinator.engaged = false
            coordinator.scrollView?.isScrollEnabled = true
            onEnded(recognizer.velocity, PinchZoomScroller(scrollView: coordinator.scrollView))
            coordinator.scrollView = nil
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var engaged = false
        var startScale: CGFloat = 1.0
        weak var scrollView: UIScrollView?

        func enclosingScrollView(of view: UIView?) -> UIScrollView? {
            var current = view?.superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                current = view.superview
            }
            return nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
