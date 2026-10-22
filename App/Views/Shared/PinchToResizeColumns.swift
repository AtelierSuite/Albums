import SwiftUI
import UIKit

struct PinchToResizeColumnsModifier: ViewModifier {

    @Binding var columnCount: Int
    var range: ClosedRange<Int>
    var isEnabled: Bool

    @State private var startColumnCount: Int?

    private let stepScale = log(1.2)

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = startColumnCount ?? columnCount
                        if startColumnCount == nil {
                            startColumnCount = start
                        }
                        let steps = Int((log(max(value.magnification, 0.01)) / stepScale).rounded())
                        let target = snappedColumnCount(from: start, steps: steps)
                        guard target != columnCount else { return }
                        withAnimation(.smooth.speed(2.0)) {
                            columnCount = target
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .onEnded { _ in
                        startColumnCount = nil
                    },
                including: isEnabled ? .all : .subviews
            )
    }

    private func snappedColumnCount(from start: Int, steps: Int) -> Int {
        let proposed = start - steps
        if proposed > start {
            return max(start, min(proposed, range.upperBound))
        } else {
            return min(start, max(proposed, range.lowerBound))
        }
    }
}

extension View {
    func pinchToResizeColumns(_ columnCount: Binding<Int>,
                              range: ClosedRange<Int> = 2...10,
                              isEnabled: Bool = true) -> some View {
        modifier(PinchToResizeColumnsModifier(columnCount: columnCount, range: range, isEnabled: isEnabled))
    }
}
