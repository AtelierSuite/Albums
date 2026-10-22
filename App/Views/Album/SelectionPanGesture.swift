import SwiftUI
import UIKit

final class DirectionalSelectionPanRecognizer: UIPanGestureRecognizer {

    var directionThreshold = 10.0
    private var startLocation: CGPoint = .zero
    private var resolved = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        startLocation = touches.first?.location(in: view) ?? .zero
        resolved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !resolved else {
            super.touchesMoved(touches, with: event)
            return
        }
        guard let point = touches.first?.location(in: view) else { return }
        let deltaX = point.x - startLocation.x
        let deltaY = point.y - startLocation.y
        guard abs(deltaX) >= directionThreshold || abs(deltaY) >= directionThreshold else { return }
        resolved = true
        if abs(deltaX) > abs(deltaY) {
            super.touchesMoved(touches, with: event)
        } else {
            state = .failed
        }
    }
}

struct SelectionPanGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool
    var coordinateSpace: String
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> DirectionalSelectionPanRecognizer {
        let recognizer = DirectionalSelectionPanRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: DirectionalSelectionPanRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: DirectionalSelectionPanRecognizer, context: Context) {
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            coordinator.engaged = true
            coordinator.onPaint = onChange
            coordinator.lockedScrollView = recognizer.scrollViewUnderTouch
            let location = context.converter.location(in: .named(coordinateSpace))
            coordinator.lastLocation = location
            onChange(location)
            coordinator.updateAutoScroll(recognizer: recognizer)
            coordinator.startAutoScroll()
        case .changed:
            guard coordinator.engaged else { return }
            let location = context.converter.location(in: .named(coordinateSpace))
            coordinator.lastLocation = location
            onChange(location)
            coordinator.updateAutoScroll(recognizer: recognizer)
        case .ended, .cancelled, .failed:
            coordinator.stopAutoScroll()
            coordinator.lockedScrollView = nil
            if coordinator.engaged {
                onEnd()
            }
            coordinator.engaged = false
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var engaged = false
        weak var lockedScrollView: UIScrollView?
        var onPaint: ((CGPoint) -> Void)?
        var lastLocation: CGPoint = .zero
        var autoScrollVelocity: CGFloat = 0.0
        private var displayLink: CADisplayLink?

        private let edgeBand = 90.0
        private let maxScrollSpeed = 700.0

        func updateAutoScroll(recognizer: UIPanGestureRecognizer) {
            guard let scrollView = lockedScrollView else {
                autoScrollVelocity = 0.0
                return
            }
            let viewportY = recognizer.location(in: scrollView).y - scrollView.contentOffset.y
            let height = scrollView.bounds.height
            if viewportY < edgeBand {
                let intensity = min(max((edgeBand - viewportY) / edgeBand, 0.0), 1.0)
                autoScrollVelocity = -maxScrollSpeed * intensity
            } else if viewportY > height - edgeBand {
                let intensity = min(max((viewportY - (height - edgeBand)) / edgeBand, 0.0), 1.0)
                autoScrollVelocity = maxScrollSpeed * intensity
            } else {
                autoScrollVelocity = 0.0
            }
        }

        func startAutoScroll() {
            stopAutoScroll()
            let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopAutoScroll() {
            displayLink?.invalidate()
            displayLink = nil
            autoScrollVelocity = 0.0
        }

        @objc private func autoScrollTick(_ link: CADisplayLink) {
            guard autoScrollVelocity != 0.0, let scrollView = lockedScrollView else { return }
            let maxOffset = max(0.0, scrollView.contentSize.height - scrollView.bounds.height)
            let oldOffset = scrollView.contentOffset.y
            let newOffset = min(max(oldOffset + autoScrollVelocity * link.duration, 0.0), maxOffset)
            let delta = newOffset - oldOffset
            if delta == 0.0 { return }
            scrollView.contentOffset.y = newOffset
            lastLocation.y += delta
            onPaint?(lastLocation)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}
