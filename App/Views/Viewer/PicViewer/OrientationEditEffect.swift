import Engine
import SwiftUI

struct OrientationEditEffect: ViewModifier {

    let edit: PicOrientationEdit
    let containerSize: CGSize

    @State private var contentSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                contentSize = newSize
            }
            .rotationEffect(.degrees(Double(edit.quarterTurns) * -90.0))
            .rotation3DEffect(.degrees(edit.isMirrored ? 180.0 : 0.0), axis: (x: 0.0, y: 1.0, z: 0.0))
            .scaleEffect(fitScale)
    }

    private var fitScale: CGFloat {
        guard edit.swapsDimensions,
              contentSize.width > 0.0, contentSize.height > 0.0,
              containerSize.width > 0.0, containerSize.height > 0.0 else { return 1.0 }
        return min(containerSize.width / contentSize.height, containerSize.height / contentSize.width)
    }
}

extension View {
    func orientationEdit(_ edit: PicOrientationEdit, in containerSize: CGSize) -> some View {
        modifier(OrientationEditEffect(edit: edit, containerSize: containerSize))
    }
}
