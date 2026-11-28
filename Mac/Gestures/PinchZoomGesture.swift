import AppKit
import SwiftUI

@MainActor
struct PinchZoomScroller {

    weak var scrollView: NSScrollView?

    func clampedDelta(_ delta: CGFloat, contentHeightChange: CGFloat) -> CGFloat {
        guard let scrollView, let documentView = scrollView.documentView else { return 0.0 }
        let clipView = scrollView.contentView
        let inset = clipView.contentInsets
        let minimum = -inset.top
        let maximum = max(minimum, documentView.frame.height + contentHeightChange
                          + inset.bottom - clipView.bounds.height)
        let current = clipView.bounds.origin.y
        return min(max(current + delta, minimum), maximum) - current
    }

    func layoutAndScroll(by delta: CGFloat) {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        let target = clipView.bounds.origin.y + delta
        scrollView.window?.layoutIfNeeded()
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clipView)
    }

    static func underPointer() -> (NSScrollView, NSPoint)? {
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return nil }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        var view = contentView.hitTest(contentView.convert(pointInWindow, from: nil))
        while let current = view {
            if let scrollView = current as? NSScrollView ?? current.enclosingScrollView {
                return (scrollView, scrollView.contentView.convert(pointInWindow, from: nil))
            }
            view = current.superview
        }
        return nil
    }
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
                if PinchSession.begins(at: value.startLocation, time: value.time) {
                    let location = value.startLocation
                    var viewport = CGRect(x: 0.0, y: location.y - 1000.0, width: 0.0, height: 2000.0)
                    let found = PinchZoomScroller.underPointer()
                    if let (scrollView, pointInClip) = found {
                        viewport = scrollView.contentView.bounds.offsetBy(dx: location.x - pointInClip.x,
                                                                          dy: location.y - pointInClip.y)
                    }
                    PinchSession.scrollView = found?.0
                    onBegan(location, viewport, PinchZoomScroller(scrollView: found?.0))
                }
                onChanged(value.magnification, value.startLocation,
                          PinchZoomScroller(scrollView: PinchSession.scrollView))
            }
            .onEnded { value in
                let scroller = PinchZoomScroller(scrollView: PinchSession.scrollView)
                PinchSession.end()
                onEnded(value.velocity, scroller)
            }
    }
}

@MainActor
private enum PinchSession {

    private static var startLocation: CGPoint?
    private static var lastTime: Date = .distantPast
    static weak var scrollView: NSScrollView?

    // A pinch that never reports its end would otherwise block every later one.
    static func begins(at location: CGPoint, time: Date) -> Bool {
        defer {
            startLocation = location
            lastTime = time
        }
        return startLocation != location || time.timeIntervalSince(lastTime) > 0.25
    }

    static func end() {
        startLocation = nil
        scrollView = nil
    }
}
