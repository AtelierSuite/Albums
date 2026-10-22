import SwiftUI
import UIKit

enum PinchZoomRenderer<Cell: View> {
    case images(cached: (Int) -> UIImage?, load: (Int) async -> UIImage?)
    case views((Int) -> Cell)
}

struct PinchZoomGrid<Content: View, Cell: View>: View {

    var columnCount: Int
    var itemCount: Int
    var range: ClosedRange<Int>
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var measuresCellHeight: Bool
    var resizesDuringZoom: Bool
    var cropsToTop: Bool
    var onColumnCountChange: ((Int) -> Void)?
    var renderer: PinchZoomRenderer<Cell>
    var content: () -> Content

    private static var coordinateSpace: String { "PinchZoomGridSpace" }

    @State private var zoom = PinchZoomState()
    @State private var gridSize: CGSize = .zero

    var body: some View {
        content()
            .opacity(zoom.session == nil ? 1.0 : 0.0)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                gridSize = size
            }
            .modifier(PinchZoomHeightModifier(session: resizesDuringZoom ? zoom.session : nil,
                                              progress: zoom.progress,
                                              focusY: zoom.focusY))
            .overlay(alignment: .topLeading) {
                PinchZoomOverlay(zoom: zoom, renderer: renderer)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.coordinateSpace))
            .gesture(PinchZoomGesture(isEnabled: onColumnCountChange != nil && !zoom.isSettling,
                                      coordinateSpace: Self.coordinateSpace,
                                      onBegan: { location, viewport, _ in begin(at: location, viewport: viewport) },
                                      onChanged: { scale, location, _ in update(scale: scale, location: location) },
                                      onEnded: { end(velocity: $0, scroller: $1) }))
    }

    private func begin(at location: CGPoint, viewport: CGRect) {
        guard gridSize.width > 0.0, itemCount > 0, !zoom.isSettling else { return }
        let start = columnCount
        let cellWidth = PinchZoomSession.cellWidth(columns: CGFloat(start), width: gridSize.width,
                                                   spacing: columnSpacing)
        var extraHeight = 0.0
        if measuresCellHeight {
            let rows = CGFloat((itemCount + start - 1) / start)
            extraHeight = max((gridSize.height - (rows - 1.0) * rowSpacing) / rows - cellWidth, 0.0)
        }
        let cellHeight = cellWidth + extraHeight
        let rowPitch = cellHeight + rowSpacing
        let row = max(Int(location.y / rowPitch), 0)
        let column = min(max(Int(location.x / (cellWidth + columnSpacing)), 0), start - 1)
        let fraction = min(max((location.y - CGFloat(row) * rowPitch) / cellHeight, 0.0), 1.0)
        zoom.session = PinchZoomSession(startCount: start,
                                        lower: min(range.lowerBound, start),
                                        upper: max(range.upperBound, start),
                                        width: gridSize.width,
                                        columnSpacing: columnSpacing,
                                        rowSpacing: rowSpacing,
                                        extraHeight: extraHeight,
                                        cropsToTop: cropsToTop,
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
        let currentHeight = resizesDuringZoom
            ? session.contentBottom(progress: progress, focusY: zoom.focusY)
            : session.gridHeight(columns: session.startCount)
        let heightChange = session.gridHeight(columns: target) - currentHeight
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
                zoom.session = nil
                zoom.isSettling = false
                scroller.layoutAndScroll(by: scrollDelta)
            }
        }
    }
}

extension PinchZoomGrid where Cell == EmptyView {
    init(columnCount: Int,
         itemCount: Int,
         range: ClosedRange<Int> = 2...10,
         spacing: CGFloat = 2.0,
         cropsToTop: Bool = false,
         onColumnCountChange: ((Int) -> Void)?,
         cachedImage: @escaping (Int) -> UIImage?,
         loadImage: @escaping (Int) async -> UIImage?,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(columnCount: columnCount,
                  itemCount: itemCount,
                  range: range,
                  columnSpacing: spacing,
                  rowSpacing: spacing,
                  measuresCellHeight: false,
                  resizesDuringZoom: false,
                  cropsToTop: cropsToTop,
                  onColumnCountChange: onColumnCountChange,
                  renderer: .images(cached: cachedImage, load: loadImage),
                  content: content)
    }
}

extension PinchZoomGrid {
    init(columnCount: Int,
         itemCount: Int,
         range: ClosedRange<Int> = 2...10,
         columnSpacing: CGFloat,
         rowSpacing: CGFloat,
         onColumnCountChange: ((Int) -> Void)?,
         @ViewBuilder cell: @escaping (Int) -> Cell,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(columnCount: columnCount,
                  itemCount: itemCount,
                  range: range,
                  columnSpacing: columnSpacing,
                  rowSpacing: rowSpacing,
                  measuresCellHeight: true,
                  resizesDuringZoom: true,
                  cropsToTop: false,
                  onColumnCountChange: onColumnCountChange,
                  renderer: .views(cell),
                  content: content)
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
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var extraHeight: CGFloat
    var cropsToTop: Bool
    var itemCount: Int
    var viewport: CGRect
    var anchorIndex: Int
    var anchorFraction: CGFloat

    static func cellWidth(columns: CGFloat, width: CGFloat, spacing: CGFloat) -> CGFloat {
        max((width - spacing * (columns - 1.0)) / columns, 1.0)
    }

    func cellWidth(columns: CGFloat) -> CGFloat {
        Self.cellWidth(columns: columns, width: width, spacing: columnSpacing)
    }

    func cellHeight(columns: CGFloat) -> CGFloat {
        cellWidth(columns: columns) + extraHeight
    }

    func columns(forCellWidth cellWidth: CGFloat) -> CGFloat {
        (width + columnSpacing) / (cellWidth + columnSpacing)
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
        let cellHeight = cellHeight(columns: CGFloat(columns))
        return CGFloat(anchorIndex / columns) * (cellHeight + rowSpacing) + anchorFraction * cellHeight
    }

    func gridHeight(columns: Int) -> CGFloat {
        guard itemCount > 0 else { return 0.0 }
        let rows = (itemCount + columns - 1) / columns
        return CGFloat(rows) * cellHeight(columns: CGFloat(columns)) + CGFloat(rows - 1) * rowSpacing
    }

    func morph(progress: CGFloat) -> PinchZoomMorph {
        let fewer = min(max(Int(progress.rounded(.down)), lower), upper)
        let more = min(fewer + 1, upper)
        let fraction = more == fewer ? 0.0 : min(max((progress - CGFloat(fewer) - 0.35) / 0.3, 0.0), 1.0)
        let cellWidth = cellWidth(columns: progress)
        let cellHeight = cellWidth + extraHeight
        return PinchZoomMorph(fewerColumns: fewer,
                              moreColumns: more,
                              blend: fraction * fraction * (3.0 - 2.0 * fraction),
                              cellWidth: cellWidth,
                              cellHeight: cellHeight,
                              columnPitch: cellWidth + columnSpacing,
                              rowPitch: cellHeight + rowSpacing)
    }

    func cellOrigin(index: Int, columns: Int, morph: PinchZoomMorph, focusY: CGFloat) -> CGPoint {
        let anchorTop = focusY - anchorFraction * morph.cellHeight
        return CGPoint(x: CGFloat(index % columns) * morph.columnPitch,
                       y: anchorTop + CGFloat(index / columns - anchorIndex / columns) * morph.rowPitch)
    }

    func visibleItems(columns: Int, morph: PinchZoomMorph, focusY: CGFloat) -> Range<Int> {
        let anchorTop = focusY - anchorFraction * morph.cellHeight
        let anchorRow = anchorIndex / columns
        let firstRow = max(anchorRow + Int(((viewport.minY - anchorTop) / morph.rowPitch).rounded(.down)), 0)
        let lastRow = anchorRow + Int(((viewport.maxY - anchorTop) / morph.rowPitch).rounded(.down))
        let first = min(firstRow * columns, itemCount)
        let last = min(max((lastRow + 1) * columns, first), itemCount)
        return first..<last
    }

    func contentBottom(progress: CGFloat, focusY: CGFloat) -> CGFloat {
        let morph = morph(progress: progress)
        func bottom(columns: Int) -> CGFloat {
            let rows = (itemCount + columns - 1) / columns
            let top = cellOrigin(index: 0, columns: columns, morph: morph, focusY: focusY).y
            return top + CGFloat(rows) * morph.rowPitch - rowSpacing
        }
        let fewer = bottom(columns: morph.fewerColumns)
        let more = bottom(columns: morph.moreColumns)
        return max(fewer + (more - fewer) * morph.blend, 0.0)
    }

    func placements(progress: CGFloat, focusY: CGFloat) -> [PinchZoomPlacement] {
        let morph = morph(progress: progress)
        let fewerItems = visibleItems(columns: morph.fewerColumns, morph: morph, focusY: focusY)
        let moreItems = visibleItems(columns: morph.moreColumns, morph: morph, focusY: focusY)
        let items = min(fewerItems.lowerBound, moreItems.lowerBound)..<max(fewerItems.upperBound, moreItems.upperBound)
        var placements: [PinchZoomPlacement] = []
        for index in items {
            let start = cellOrigin(index: index, columns: morph.fewerColumns, morph: morph, focusY: focusY)
            let end = cellOrigin(index: index, columns: morph.moreColumns, morph: morph, focusY: focusY)
            if abs(end.x - start.x) > morph.columnPitch * 1.5 {
                placements.append(PinchZoomPlacement(index: index, isGhost: false,
                                                     origin: start, opacity: 1.0 - morph.blend))
                placements.append(PinchZoomPlacement(index: index, isGhost: true,
                                                     origin: end, opacity: morph.blend))
            } else {
                placements.append(PinchZoomPlacement(index: index, isGhost: false,
                                                     origin: CGPoint(x: start.x + (end.x - start.x) * morph.blend,
                                                                     y: start.y + (end.y - start.y) * morph.blend),
                                                     opacity: 1.0))
            }
        }
        return placements
    }
}

struct PinchZoomPlacement: Identifiable {
    var index: Int
    var isGhost: Bool
    var origin: CGPoint
    var opacity: CGFloat

    var id: Int { index * 2 + (isGhost ? 1 : 0) }
}

struct PinchZoomMorph {
    var fewerColumns: Int
    var moreColumns: Int
    var blend: CGFloat
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var columnPitch: CGFloat
    var rowPitch: CGFloat
}

@Animatable
private struct PinchZoomHeightModifier: ViewModifier {

    @AnimatableIgnored var session: PinchZoomSession?
    var progress: CGFloat
    var focusY: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: session?.contentBottom(progress: progress, focusY: focusY), alignment: .top)
    }
}

private struct PinchZoomOverlay<Cell: View>: View {

    var zoom: PinchZoomState
    var renderer: PinchZoomRenderer<Cell>

    var body: some View {
        if let session = zoom.session {
            switch renderer {
            case .images(let cachedImage, let loadImage):
                PinchZoomLayers(session: session,
                                progress: zoom.progress,
                                focusY: zoom.focusY,
                                cachedImage: cachedImage,
                                loadImage: loadImage)
            case .views(let cell):
                PinchZoomViewLayers(session: session,
                                    progress: zoom.progress,
                                    focusY: zoom.focusY,
                                    cell: cell)
            }
        }
    }
}

@Animatable
private struct PinchZoomViewLayers<Cell: View>: View {

    @AnimatableIgnored var session: PinchZoomSession
    var progress: CGFloat
    var focusY: CGFloat
    @AnimatableIgnored var cell: (Int) -> Cell

    var body: some View {
        let morph = session.morph(progress: progress)
        ZStack(alignment: .topLeading) {
            ForEach(session.placements(progress: progress, focusY: focusY)) { placement in
                cell(placement.index)
                    .frame(width: morph.cellWidth, height: morph.cellHeight, alignment: .top)
                    .opacity(placement.opacity)
                    .offset(x: placement.origin.x, y: placement.origin.y)
            }
        }
        .frame(width: session.width, height: 1.0, alignment: .topLeading)
    }
}

@Animatable
private struct PinchZoomLayers: View {

    @AnimatableIgnored var session: PinchZoomSession
    var progress: CGFloat
    var focusY: CGFloat
    @AnimatableIgnored var cachedImage: (Int) -> UIImage?
    @AnimatableIgnored var loadImage: (Int) async -> UIImage?

    var body: some View {
        PinchZoomCanvas(session: session,
                        progress: progress,
                        focusY: focusY,
                        cachedImage: cachedImage,
                        loadImage: loadImage)
            .frame(width: session.width, height: 1.0, alignment: .topLeading)
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

    func layoutAndScroll(by delta: CGFloat) {
        guard let scrollView else { return }
        let target = scrollView.contentOffset.y + delta
        // SwiftUI resets offsets set before it lays out the new content, snapping lazy stacks to the top.
        scrollView.window?.layoutIfNeeded()
        scrollView.contentOffset.y = target
    }

    func zoomSnapshot(of frame: CGRect, from anchor: CGPoint, to target: CGPoint, scale: CGFloat,
                      animation: Animation) {
        guard let scrollView, let superview = scrollView.superview else { return }
        let visible = scrollView.bounds.intersection(frame)
        guard !visible.isNull, visible.height > 0.0,
              let snapshot = scrollView.resizableSnapshotView(from: visible, afterScreenUpdates: false,
                                                              withCapInsets: .zero) else { return }
        let container = UIView(frame: scrollView.convert(visible, to: superview))
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        snapshot.frame = container.bounds
        container.addSubview(snapshot)
        superview.insertSubview(container, aboveSubview: scrollView)
        let center = CGPoint(x: visible.midX, y: visible.midY)
        let transform = CGAffineTransform(translationX: target.x - center.x - scale * (anchor.x - center.x),
                                          y: target.y - center.y - scale * (anchor.y - center.y))
            .scaledBy(x: scale, y: scale)
        UIView.animate(animation) {
            snapshot.transform = transform
            snapshot.alpha = 0.0
        } completion: {
            container.removeFromSuperview()
        }
    }
}

struct PinchZoomGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool
    var coordinateSpace: String
    var onBegan: (CGPoint, CGRect, PinchZoomScroller) -> Void
    var onChanged: (CGFloat, CGPoint, PinchZoomScroller) -> Void
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
            if let scrollView = recognizer.scrollViewUnderTouch {
                coordinator.scrollView = scrollView
                scrollView.isScrollEnabled = false
                let locationInScrollView = recognizer.location(in: scrollView)
                viewport = scrollView.bounds.offsetBy(dx: location.x - locationInScrollView.x,
                                                      dy: location.y - locationInScrollView.y)
            }
            onBegan(location, viewport, PinchZoomScroller(scrollView: coordinator.scrollView))
        case .changed:
            guard coordinator.engaged else { return }
            onChanged(recognizer.scale / coordinator.startScale,
                      context.converter.location(in: .named(coordinateSpace)),
                      PinchZoomScroller(scrollView: coordinator.scrollView))
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
