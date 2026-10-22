import SwiftUI
import UIKit

struct MasonryItem: Identifiable {
    let id: String
    let aspectRatio: CGFloat
}

struct MasonryGrid<Cell: View, MorphCell: View>: View {

    var items: [MasonryItem]
    var columnCount: Int
    var range: ClosedRange<Int>
    var width: CGFloat
    var spacing: CGFloat = 2.0
    var includedID: String?
    var onColumnCountChange: ((Int) -> Void)?
    @ViewBuilder var cell: (Int) -> Cell
    @ViewBuilder var morphCell: (Int) -> MorphCell

    private static var coordinateSpace: String { "MasonryGridSpace" }

    @State private var pinch: MasonryPinchAnchor?
    @State private var visibleRange: ClosedRange<CGFloat>?

    var body: some View {
        let layout = layout(columns: columnCount)
        ZStack(alignment: .topLeading) {
            ForEach(layout.entries(in: visibleRange, including: includedID)) { entry in
                if let frame = layout.frames[entry.id] {
                    cell(entry.index)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout.height, maxHeight: layout.height, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.bounds(of: .scrollView) ?? .infinite
        } action: { visible in
            updateVisibleRange(visible)
        }
        .opacity(pinch == nil ? 1.0 : 0.0)
        .overlay(alignment: .topLeading) {
            if let pinch {
                morphLayer(for: pinch)
            }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .gesture(PinchZoomGesture(isEnabled: onColumnCountChange != nil,
                                  coordinateSpace: Self.coordinateSpace,
                                  onBegan: { location, viewport, _ in
                                      beginPinch(at: location, viewport: viewport)
                                  },
                                  onChanged: { scale, _, scroller in
                                      updatePinch(scale: scale, scroller: scroller)
                                  },
                                  onEnded: { _, scroller in endPinch(scroller: scroller) }))
    }

    private func morphLayer(for pinch: MasonryPinchAnchor) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(pinch.entries) { entry in
                if let frame = pinch.frames[entry.id] {
                    morphCell(entry.index)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func beginPinch(at location: CGPoint, viewport: CGRect) {
        guard pinch == nil else { return }
        let start = columnCount
        let layout = layout(columns: start)
        let nearest = layout.frames.min { lhs, rhs in
            distance(from: location, to: lhs.value) < distance(from: location, to: rhs.value)
        }
        guard let nearest else { return }
        let frame = nearest.value
        let fraction = min(max((location.y - frame.minY) / frame.height, 0.0), 1.0)
        let anchorY = frame.minY + fraction * frame.height
        let lower = min(range.lowerBound, start)
        let upper = max(range.upperBound, start)
        let margin = viewport.height * 0.25
        var ids = Set<String>()
        for count in lower...upper {
            let candidate = count == start ? layout : self.layout(columns: count)
            guard let anchorFrame = candidate.frames[nearest.key] else { continue }
            let shift = anchorFrame.minY + fraction * anchorFrame.height - anchorY
            let top = viewport.minY - margin + shift
            let bottom = viewport.maxY + margin + shift
            for (id, frame) in candidate.frames where frame.maxY >= top && frame.minY <= bottom {
                ids.insert(id)
            }
        }
        pinch = MasonryPinchAnchor(startCount: start,
                                   currentCount: start,
                                   range: lower...upper,
                                   entryID: nearest.key,
                                   fraction: fraction,
                                   startAnchorY: anchorY,
                                   startHeight: layout.height,
                                   entries: layout.entries.filter { ids.contains($0.id) },
                                   frames: layout.frames.filter { ids.contains($0.key) })
    }

    // SwiftUI doesn't refresh gesture representables mid-gesture, so columnCount is stale here.
    private func updatePinch(scale: CGFloat, scroller: PinchZoomScroller) {
        guard var pinch, !pinch.hasEnded else { return }
        let steps = Int((log(max(scale, 0.01)) / log(1.2)).rounded())
        let target = min(max(pinch.startCount - steps, pinch.range.lowerBound), pinch.range.upperBound)
        guard target != pinch.currentCount else { return }
        let layout = layout(columns: target)
        guard let anchorFrame = layout.frames[pinch.entryID] else { return }
        let scrollDelta = scroller.clampedDelta(pinch.anchorY(in: anchorFrame) - pinch.startAnchorY,
                                                contentHeightChange: layout.height - pinch.startHeight)
        pinch.currentCount = target
        pinch.scrollDelta = scrollDelta
        pinch.animationsInFlight += 1
        let ids = Set(pinch.entries.map(\.id))
        pinch.frames = layout.frames
            .filter { ids.contains($0.key) }
            .mapValues { $0.offsetBy(dx: 0.0, dy: -scrollDelta) }
        withAnimation(.smooth(duration: 0.25)) {
            self.pinch = pinch
        } completion: {
            self.pinch?.animationsInFlight -= 1
            commitPinchIfSettled(scroller: scroller)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func endPinch(scroller: PinchZoomScroller) {
        guard pinch != nil else { return }
        pinch?.hasEnded = true
        commitPinchIfSettled(scroller: scroller)
    }

    private func commitPinchIfSettled(scroller: PinchZoomScroller) {
        guard let pinch, pinch.hasEnded, pinch.animationsInFlight == 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if pinch.currentCount != pinch.startCount {
                onColumnCountChange?(pinch.currentCount)
            }
            self.pinch = nil
            scroller.layoutAndScroll(by: pinch.scrollDelta)
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let horizontal = max(rect.minX - point.x, 0.0, point.x - rect.maxX)
        let vertical = max(rect.minY - point.y, 0.0, point.y - rect.maxY)
        return horizontal * horizontal + vertical * vertical
    }

    private func layout(columns requestedCount: Int) -> MasonryLayout {
        let count = max(requestedCount, 1)
        let cellWidth = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 1.0)
        var weights = Array(repeating: 0.0, count: count)
        var tops = Array(repeating: 0.0, count: count)
        var entries: [[MasonryEntry]] = Array(repeating: [], count: count)
        var frames: [String: CGRect] = [:]
        for (index, item) in items.enumerated() {
            var column = 0
            for candidate in 1..<count where weights[candidate] < weights[column] {
                column = candidate
            }
            let aspectRatio = max(item.aspectRatio, 0.01)
            weights[column] += 1.0 / aspectRatio
            let cellHeight = cellWidth / aspectRatio
            frames[item.id] = CGRect(x: CGFloat(column) * (cellWidth + spacing), y: tops[column],
                                     width: cellWidth, height: cellHeight)
            entries[column].append(MasonryEntry(id: item.id, index: index))
            tops[column] += cellHeight + spacing
        }
        let height = max((tops.max() ?? 0.0) - spacing, 0.0)
        return MasonryLayout(entries: entries.flatMap { $0 }, frames: frames, height: height)
    }

    private func updateVisibleRange(_ visible: CGRect) {
        let range: ClosedRange<CGFloat>
        if visible.isNull || visible.isInfinite || visible.height <= 0.0 {
            range = -CGFloat.infinity...CGFloat.infinity
        } else {
            let step = max(visible.height / 2.0, 100.0)
            range = ((visible.minY - visible.height) / step).rounded(.down) * step
                ... ((visible.maxY + visible.height) / step).rounded(.up) * step
        }
        if range != visibleRange {
            visibleRange = range
        }
    }
}

struct MasonryEntry: Identifiable {
    let id: String
    let index: Int
}

struct MasonryLayout {
    let entries: [MasonryEntry]
    let frames: [String: CGRect]
    let height: CGFloat

    func entries(in range: ClosedRange<CGFloat>?, including includedID: String?) -> [MasonryEntry] {
        entries.filter { entry in
            if entry.id == includedID { return true }
            guard let range, let frame = frames[entry.id] else { return false }
            return frame.maxY >= range.lowerBound && frame.minY <= range.upperBound
        }
    }
}

struct MasonryPinchAnchor {
    let startCount: Int
    var currentCount: Int
    let range: ClosedRange<Int>
    let entryID: String
    let fraction: CGFloat
    let startAnchorY: CGFloat
    let startHeight: CGFloat
    let entries: [MasonryEntry]
    var frames: [String: CGRect]
    var scrollDelta: CGFloat = 0.0
    var animationsInFlight = 0
    var hasEnded = false

    func anchorY(in frame: CGRect) -> CGFloat {
        frame.minY + fraction * frame.height
    }
}
