import SwiftUI
import UIKit

private let minimumZoomScale: CGFloat = 1.0
private let maximumZoomScale: CGFloat = 6.0
private let minimumDoubleTapZoomScale: CGFloat = 2.5
private let zoomSnapThreshold: CGFloat = 1.05

struct ZoomableModifier<ResetID: Hashable>: ViewModifier {

    @Binding var scale: CGFloat
    let contentSize: CGSize
    let resetID: ResetID
    let onTap: () -> Void

    @State private var offset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var pinchStart: PinchStart?
    @State private var panStart: PanStart?

    private struct PinchStart {
        var scale: CGFloat
        var offset: CGSize
        var location: CGPoint
    }

    private struct PanStart {
        var offset: CGSize
        var translation: CGSize
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(ZoomClipShape(isClipping: scale > minimumZoomScale))
            .contentShape(.rect)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                containerSize = newSize
                offset = clampedOffset(offset, scale: scale)
            }
            .gesture(
                ExclusiveGesture(SpatialTapGesture(count: 2), TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first(let tap): toggleZoom(at: tap.location)
                        case .second: onTap()
                        }
                    }
            )
            .gesture(ZoomPinchGesture(onBegan: beginPinch, onChanged: changePinch, onEnded: endPinch))
            .gesture(ZoomPanGesture(isEnabled: scale > minimumZoomScale,
                                    onChanged: changePan, onEnded: endPan))
            .onChange(of: resetID) {
                resetZoom(animated: false)
            }
    }

    private var center: CGPoint {
        CGPoint(x: containerSize.width / 2.0, y: containerSize.height / 2.0)
    }

    private func beginPinch(at location: CGPoint) {
        pinchStart = PinchStart(scale: scale, offset: offset, location: location)
        panStart = nil
    }

    private func changePinch(factor: CGFloat, location: CGPoint) {
        guard let start = pinchStart else { return }
        let newScale = rubberBandedScale(start.scale * factor)
        let appliedFactor = newScale / start.scale
        scale = newScale
        offset = CGSize(
            width: location.x - center.x - (start.location.x - center.x - start.offset.width) * appliedFactor,
            height: location.y - center.y - (start.location.y - center.y - start.offset.height) * appliedFactor
        )
    }

    private func endPinch(at location: CGPoint) {
        pinchStart = nil
        panStart = nil
        settle(anchoredAt: location)
    }

    private func changePan(translation: CGSize) {
        guard pinchStart == nil else {
            panStart = nil
            return
        }
        guard let start = panStart else {
            panStart = PanStart(offset: offset, translation: translation)
            return
        }
        let proposed = CGSize(width: start.offset.width + translation.width - start.translation.width,
                              height: start.offset.height + translation.height - start.translation.height)
        offset = rubberBandedOffset(proposed, scale: scale)
    }

    private func endPan(velocity: CGSize) {
        guard pinchStart == nil, panStart != nil else { return }
        panStart = nil
        let projected = CGSize(width: offset.width + velocity.width * 0.2,
                               height: offset.height + velocity.height * 0.2)
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1.0, duration: 0.45)) {
            offset = clampedOffset(projected, scale: scale)
        }
    }

    private func settle(anchoredAt location: CGPoint) {
        let target = min(max(scale, minimumZoomScale), maximumZoomScale)
        guard target >= zoomSnapThreshold else {
            resetZoom(animated: true)
            return
        }
        let factor = target / scale
        let anchored = CGSize(
            width: (location.x - center.x) * (1.0 - factor) + offset.width * factor,
            height: (location.y - center.y) * (1.0 - factor) + offset.height * factor
        )
        withAnimation(.smooth(duration: 0.3)) {
            scale = target
            offset = clampedOffset(anchored, scale: target)
        }
    }

    private func toggleZoom(at location: CGPoint) {
        guard scale <= minimumZoomScale else {
            resetZoom(animated: true)
            return
        }
        let target = doubleTapZoomScale
        let zoomed = CGSize(width: (location.x - center.x) * (1.0 - target),
                            height: (location.y - center.y) * (1.0 - target))
        withAnimation(.smooth(duration: 0.3)) {
            scale = target
            offset = clampedOffset(zoomed, scale: target)
        }
    }

    private func resetZoom(animated: Bool) {
        pinchStart = nil
        panStart = nil
        var transaction = Transaction(animation: animated ? .smooth(duration: 0.3) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            scale = minimumZoomScale
            offset = .zero
        }
    }

    private var doubleTapZoomScale: CGFloat {
        guard contentSize.width > 0.0, contentSize.height > 0.0 else { return minimumDoubleTapZoomScale }
        let fillScale = max(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return min(max(fillScale, minimumDoubleTapZoomScale), maximumZoomScale)
    }

    private func offsetLimits(scale: CGFloat) -> CGSize {
        CGSize(width: max(0.0, (contentSize.width * scale - containerSize.width) / 2.0),
               height: max(0.0, (contentSize.height * scale - containerSize.height) / 2.0))
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let limits = offsetLimits(scale: scale)
        return CGSize(width: min(max(proposed.width, -limits.width), limits.width),
                      height: min(max(proposed.height, -limits.height), limits.height))
    }

    private func rubberBandedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let limits = offsetLimits(scale: scale)
        return CGSize(width: rubberBand(proposed.width, limit: limits.width, dimension: containerSize.width),
                      height: rubberBand(proposed.height, limit: limits.height, dimension: containerSize.height))
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        let overshoot = abs(value) - limit
        guard overshoot > 0.0, dimension > 0.0 else { return value }
        let damped = (1.0 - 1.0 / (overshoot * 0.55 / dimension + 1.0)) * dimension
        return (limit + damped) * (value < 0.0 ? -1.0 : 1.0)
    }

    private func rubberBandedScale(_ proposed: CGFloat) -> CGFloat {
        if proposed < minimumZoomScale {
            return minimumZoomScale * pow(proposed / minimumZoomScale, 0.5)
        } else if proposed > maximumZoomScale {
            return maximumZoomScale * pow(proposed / maximumZoomScale, 0.3)
        }
        return proposed
    }
}

private struct ZoomClipShape: Shape {

    var isClipping: Bool

    func path(in rect: CGRect) -> Path {
        Path(isClipping ? rect : rect.insetBy(dx: -100_000.0, dy: -100_000.0))
    }
}

private struct ZoomPinchGesture: UIGestureRecognizerRepresentable {

    var onBegan: (CGPoint) -> Void
    var onChanged: (CGFloat, CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            context.coordinator.touchCount = recognizer.numberOfTouches
            recognizer.scale = 1.0
            onBegan(location)
        case .changed:
            // The centroid jumps when a finger is added or lifted mid-pinch, so restart from here.
            if recognizer.numberOfTouches != context.coordinator.touchCount {
                context.coordinator.touchCount = recognizer.numberOfTouches
                recognizer.scale = 1.0
                onBegan(location)
            } else {
                onChanged(recognizer.scale, location)
            }
        case .ended, .cancelled, .failed:
            onEnded(location)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var touchCount = 0

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct ZoomPanGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        context.coordinator.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation ?? .zero
        let velocity = context.converter.localVelocity ?? .zero
        switch recognizer.state {
        case .began, .changed:
            onChanged(CGSize(width: translation.x, height: translation.y))
        case .ended:
            onEnded(CGSize(width: velocity.x, height: velocity.y))
        case .cancelled, .failed:
            onEnded(.zero)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var isEnabled = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isEnabled
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    func zoomable(scale: Binding<CGFloat>, contentSize: CGSize, resetID: some Hashable,
                  onTap: @escaping () -> Void) -> some View {
        modifier(ZoomableModifier(scale: scale, contentSize: contentSize, resetID: resetID, onTap: onTap))
    }
}

func aspectFitSize(_ size: CGSize, in container: CGSize) -> CGSize {
    guard size.width > 0.0, size.height > 0.0 else { return container }
    let fit = min(container.width / size.width, container.height / size.height)
    return CGSize(width: size.width * fit, height: size.height * fit)
}
