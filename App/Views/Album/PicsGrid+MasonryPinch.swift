import SwiftUI
import UIKit

extension PicsGrid {

    func masonryMorphLayer(for pinch: MasonryPinchAnchor) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(pinch.entries) { entry in
                if let frame = pinch.frames[entry.id] {
                    Group {
                        if let pic = entry.pic {
                            picCellBase(for: pic, maintainsAspectRatio: true)
                        } else {
                            placeholderCell
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    func beginMasonryPinch(at location: CGPoint, viewport: CGRect) {
        guard masonryPinch == nil else { return }
        let start = fittedColumnCount
        let layout = masonryLayout(columns: start)
        let nearest = layout.frames.min { lhs, rhs in
            distance(from: location, to: lhs.value) < distance(from: location, to: rhs.value)
        }
        guard let nearest else { return }
        let frame = nearest.value
        let fraction = min(max((location.y - frame.minY) / frame.height, 0.0), 1.0)
        let anchorY = frame.minY + fraction * frame.height
        let range = GridColumnLimit.pics.range(width: gridWidth)
        let lower = min(range.lowerBound, start)
        let upper = max(range.upperBound, start)
        let margin = viewport.height * 0.25
        var ids = Set<String>()
        for count in lower...upper {
            let candidate = count == start ? layout : masonryLayout(columns: count)
            guard let anchorFrame = candidate.frames[nearest.key] else { continue }
            let shift = anchorFrame.minY + fraction * anchorFrame.height - anchorY
            let top = viewport.minY - margin + shift
            let bottom = viewport.maxY + margin + shift
            for (id, frame) in candidate.frames where frame.maxY >= top && frame.minY <= bottom {
                ids.insert(id)
            }
        }
        masonryPinch = MasonryPinchAnchor(startCount: start,
                                          currentCount: start,
                                          range: lower...upper,
                                          entryID: nearest.key,
                                          fraction: fraction,
                                          startAnchorY: anchorY,
                                          startHeight: layout.height,
                                          entries: masonryColumns(count: start).flatMap { $0 }
                                              .filter { ids.contains($0.id) },
                                          frames: layout.frames.filter { ids.contains($0.key) })
    }

    // SwiftUI doesn't refresh gesture representables mid-gesture, so columnCount is stale here.
    func updateMasonryPinch(scale: CGFloat, scroller: PinchZoomScroller) {
        guard var pinch = masonryPinch, !pinch.hasEnded else { return }
        let steps = Int((log(max(scale, 0.01)) / log(1.2)).rounded())
        let target = min(max(pinch.startCount - steps, pinch.range.lowerBound), pinch.range.upperBound)
        guard target != pinch.currentCount else { return }
        let layout = masonryLayout(columns: target)
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
            masonryPinch = pinch
        } completion: {
            masonryPinch?.animationsInFlight -= 1
            commitMasonryPinchIfSettled(scroller: scroller)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func endMasonryPinch(scroller: PinchZoomScroller) {
        guard masonryPinch != nil else { return }
        masonryPinch?.hasEnded = true
        commitMasonryPinchIfSettled(scroller: scroller)
    }

    func commitMasonryPinchIfSettled(scroller: PinchZoomScroller) {
        guard let pinch = masonryPinch, pinch.hasEnded, pinch.animationsInFlight == 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if pinch.currentCount != pinch.startCount {
                onColumnCountChange?(pinch.currentCount)
            }
            masonryPinch = nil
            scroller.layoutAndScroll(by: pinch.scrollDelta)
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let horizontal = max(rect.minX - point.x, 0.0, point.x - rect.maxX)
        let vertical = max(rect.minY - point.y, 0.0, point.y - rect.maxY)
        return horizontal * horizontal + vertical * vertical
    }

    func masonryLayout(columns count: Int) -> MasonryLayout {
        let columns = masonryColumns(count: count)
        let cellWidth = max((gridWidth - 2.0 * CGFloat(columns.count - 1)) / CGFloat(columns.count), 1.0)
        var frames: [String: CGRect] = [:]
        var height = 0.0
        for (index, column) in columns.enumerated() {
            var top = 0.0
            for entry in column {
                let cellHeight = cellWidth / max(entry.aspectRatio, 0.01)
                frames[entry.id] = CGRect(x: CGFloat(index) * (cellWidth + 2.0), y: top,
                                          width: cellWidth, height: cellHeight)
                top += cellHeight + 2.0
            }
            height = max(height, top - 2.0)
        }
        return MasonryLayout(entries: columns.flatMap { $0 }, frames: frames, height: height)
    }

    func updateMasonryVisibleRange(_ visible: CGRect) {
        let range: ClosedRange<CGFloat>
        if visible.isNull || visible.isInfinite || visible.height <= 0.0 {
            range = -CGFloat.infinity...CGFloat.infinity
        } else {
            let step = max(visible.height / 2.0, 100.0)
            range = ((visible.minY - visible.height) / step).rounded(.down) * step
                ... ((visible.maxY + visible.height) / step).rounded(.up) * step
        }
        if range != masonryVisibleRange {
            masonryVisibleRange = range
        }
    }
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
