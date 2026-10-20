import Engine
import SwiftUI

struct OrientationEditEffect: ViewModifier {

    let edit: PicOrientationEdit
    let imageSize: CGSize
    let containerSize: CGSize

    func body(content: Content) -> some View {
        content
            .modifier(OrientationTransform(
                rotation: Double(edit.quarterTurns) * -90.0,
                flip: edit.isMirrored ? 180.0 : 0.0,
                scale: fitScale
            ))
    }

    private var fitScale: CGFloat {
        guard edit.swapsDimensions,
              imageSize.width > 0.0, imageSize.height > 0.0,
              containerSize.width > 0.0, containerSize.height > 0.0 else { return 1.0 }
        let fit = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedWidth = imageSize.width * fit
        let fittedHeight = imageSize.height * fit
        return min(containerSize.width / fittedHeight, containerSize.height / fittedWidth)
    }
}

private struct OrientationTransform: GeometryEffect {

    var rotation: Double
    var flip: Double
    var scale: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(rotation, AnimatablePair(flip, scale)) }
        set {
            rotation = newValue.first
            flip = newValue.second.first
            scale = newValue.second.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let centerX = size.width / 2.0
        let centerY = size.height / 2.0
        let flipRadians = flip * .pi / 180.0
        guard abs(sin(flipRadians)) > 0.0001 else {
            let mirror: CGFloat = cos(flipRadians) < 0.0 ? -1.0 : 1.0
            return ProjectionTransform(
                CGAffineTransform(translationX: -centerX, y: -centerY)
                    .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180.0))
                    .concatenating(CGAffineTransform(scaleX: mirror * scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: centerX, y: centerY))
            )
        }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / max(size.width, size.height, 1.0)
        let flipTransform = CATransform3DConcat(CATransform3DMakeRotation(flipRadians, 0.0, 1.0, 0.0),
                                                perspective)
        var transform = CATransform3DMakeTranslation(-centerX, -centerY, 0.0)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(rotation * .pi / 180.0, 0.0, 0.0, 1.0))
        transform = CATransform3DConcat(transform, flipTransform)
        transform = CATransform3DConcat(transform, CATransform3DMakeScale(scale, scale, 1.0))
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(centerX, centerY, 0.0))
        return ProjectionTransform(transform)
    }
}

extension View {
    func orientationEdit(_ edit: PicOrientationEdit, imageSize: CGSize, in containerSize: CGSize) -> some View {
        modifier(OrientationEditEffect(edit: edit, imageSize: imageSize, containerSize: containerSize))
    }
}
