import SwiftUI
import UIKit

final class HorizontalPanRecognizer: UIPanGestureRecognizer {

    var directionThreshold = 15.0
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

struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool = true
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanRecognizer {
        let recognizer = HorizontalPanRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: HorizontalPanRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        let velocity = recognizer.velocity(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            // UIKit has no equivalent of DragGesture's predictedEndTranslation, so project
            // the flick the way UIScrollView does when it decelerates.
            onEnded(translation, translation + velocity * 0.25, velocity)
        case .cancelled, .failed:
            onEnded(translation, translation, 0.0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
