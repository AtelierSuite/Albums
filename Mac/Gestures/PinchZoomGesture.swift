import AppKit
import SwiftUI

@MainActor
struct PinchZoomScroller {

    weak var scrollView: NSScrollView?

    func clampedDelta(_ delta: CGFloat, contentHeightChange: CGFloat) -> CGFloat {
        0.0
    }

    func layoutAndScroll(by delta: CGFloat) {}
}

struct PinchZoomGesture: Gesture {

    var isEnabled: Bool
    var coordinateSpace: String
    var onBegan: (CGPoint, CGRect, PinchZoomScroller) -> Void
    var onChanged: (CGFloat, CGPoint, PinchZoomScroller) -> Void
    var onEnded: (CGFloat, PinchZoomScroller) -> Void

    var body: some Gesture {
        MagnifyGesture(minimumScaleDelta: isEnabled ? 0.0 : .greatestFiniteMagnitude)
            .onChanged { value in
                let scroller = PinchZoomScroller()
                if MacGestureTracker.begin(.gridPinch) {
                    let location = value.startLocation
                    let viewport = CGRect(x: 0.0, y: location.y - 1000.0, width: 0.0, height: 2000.0)
                    onBegan(location, viewport, scroller)
                }
                onChanged(value.magnification, value.startLocation, scroller)
            }
            .onEnded { value in
                MacGestureTracker.end(.gridPinch)
                onEnded(value.velocity, PinchZoomScroller())
            }
    }
}
