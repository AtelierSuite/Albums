import SwiftUI

struct SelectionPanGesture: Gesture {

    var isEnabled: Bool
    var coordinateSpace: String
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void

    var body: some Gesture {
        DragGesture(minimumDistance: isEnabled ? 6.0 : .greatestFiniteMagnitude,
                    coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                onChange(value.location)
            }
            .onEnded { _ in
                onEnd()
            }
    }
}
