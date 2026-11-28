import SwiftUI

struct HorizontalSwipeGesture: Gesture {

    var isEnabled: Bool = true
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat, CGFloat) -> Void

    var body: some Gesture {
        DragGesture(minimumDistance: isEnabled ? 15.0 : .greatestFiniteMagnitude)
            .onChanged { value in
                onChanged(value.translation.width)
            }
            .onEnded { value in
                onEnded(value.translation.width, value.predictedEndTranslation.width, value.velocity.width)
            }
    }
}
