import SwiftUI
import UIKit

private let minimumZoomScale: CGFloat = 1.0
private let maximumZoomScale: CGFloat = 6.0
private let minimumDoubleTapZoomScale: CGFloat = 2.5
private let zoomSnapThreshold: CGFloat = 1.05

struct ZoomableModifier<ResetID: Hashable>: ViewModifier {

    @Binding var scale: CGFloat
    let contentSize: CGSize
    let viewport: CGRect
    let resetID: ResetID
    let onTap: () -> Void

    @State private var offset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var containerFrame: CGRect = .zero
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
            .contentShape(ZoomHitShape(isExpanded: scale > minimumZoomScale))
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                containerSize = newSize
                offset = clampedOffset(offset, scale: scale)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                containerFrame = newFrame
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
            .gesture(ZoomPinchGesture(blocksDismissal: blocksDismissal,
                                      onBegan: beginPinch, onChanged: changePinch, onEnded: endPinch))
            .gesture(ZoomPanGesture(isEnabled: scale > minimumZoomScale,
                                    onChanged: changePan, onEnded: endPan))
            .onChange(of: resetID) {
                resetZoom(animated: false)
            }
    }

    private var blocksDismissal: Bool {
        scale > minimumZoomScale || (pinchStart?.scale ?? minimumZoomScale) > minimumZoomScale
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

    private var localViewport: CGRect {
        guard viewport.width > 0.0, viewport.height > 0.0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        return viewport.offsetBy(dx: -containerFrame.minX, dy: -containerFrame.minY)
    }

    private func offsetRanges(scale: CGFloat) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let viewport = localViewport
        return (offsetRange(length: contentSize.width * scale, container: containerSize.width,
                            viewportMin: viewport.minX, viewportMax: viewport.maxX),
                offsetRange(length: contentSize.height * scale, container: containerSize.height,
                            viewportMin: viewport.minY, viewportMax: viewport.maxY))
    }

    private func offsetRange(length: CGFloat, container: CGFloat,
                             viewportMin: CGFloat, viewportMax: CGFloat) -> ClosedRange<CGFloat> {
        let center = container / 2.0
        let viewportLength = viewportMax - viewportMin
        if length >= viewportLength {
            return (viewportMax - length / 2.0 - center)...(viewportMin + length / 2.0 - center)
        }
        let span = viewportLength - container
        let progress = span > 0.0 ? min(max((length - container) / span, 0.0), 1.0) : 0.0
        let centered = progress * ((viewportMin + viewportMax) / 2.0 - center)
        return centered...centered
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let ranges = offsetRanges(scale: scale)
        return CGSize(width: min(max(proposed.width, ranges.x.lowerBound), ranges.x.upperBound),
                      height: min(max(proposed.height, ranges.y.lowerBound), ranges.y.upperBound))
    }

    private func rubberBandedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let ranges = offsetRanges(scale: scale)
        return CGSize(width: rubberBand(proposed.width, within: ranges.x, dimension: containerSize.width),
                      height: rubberBand(proposed.height, within: ranges.y, dimension: containerSize.height))
    }

    private func rubberBand(_ value: CGFloat, within range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        guard dimension > 0.0 else { return value }
        func damped(_ overshoot: CGFloat) -> CGFloat {
            (1.0 - 1.0 / (overshoot * 0.55 / dimension + 1.0)) * dimension
        }
        if value < range.lowerBound {
            return range.lowerBound - damped(range.lowerBound - value)
        } else if value > range.upperBound {
            return range.upperBound + damped(value - range.upperBound)
        }
        return value
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

private struct ZoomHitShape: Shape {

    var isExpanded: Bool

    func path(in rect: CGRect) -> Path {
        Path(isExpanded ? rect.insetBy(dx: -100_000.0, dy: -100_000.0) : rect)
    }
}

private struct ZoomHiddenModifier: ViewModifier {

    let isZoomed: Bool
    let edge: Edge

    func body(content: Content) -> some View {
        content
            .opacity(isZoomed ? 0.0 : 1.0)
            .offset(x: isZoomed ? hiddenOffset.width : 0.0, y: isZoomed ? hiddenOffset.height : 0.0)
            .allowsHitTesting(!isZoomed)
            .animation(.smooth(duration: 0.3), value: isZoomed)
    }

    private var hiddenOffset: CGSize {
        switch edge {
        case .top: CGSize(width: 0.0, height: -24.0)
        case .bottom: CGSize(width: 0.0, height: 24.0)
        case .leading: CGSize(width: -24.0, height: 0.0)
        case .trailing: CGSize(width: 24.0, height: 0.0)
        }
    }
}

private struct ZoomPinchGesture: UIGestureRecognizerRepresentable {

    var blocksDismissal: Bool
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGFloat, CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        context.coordinator.blocksDismissal = blocksDismissal
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        context.coordinator.blocksDismissal = blocksDismissal
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
        var blocksDismissal = false

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // The zoom navigation transition's dismiss pan also tracks two-finger pinches, so it would pop the viewer while zooming out.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard blocksDismissal,
                  otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
            else { return false }
            return !(otherGestureRecognizer.delegate is ZoomPanGesture.Coordinator)
                && !(otherGestureRecognizer is HorizontalPanRecognizer)
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
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPinchGestureRecognizer
        }

        // The zoom navigation transition's interactive dismiss pan would otherwise win and pop the viewer.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            !(otherGestureRecognizer is UIPinchGestureRecognizer)
        }
    }
}

extension View {
    func hiddenWhileZoomed(_ isZoomed: Bool, toward edge: Edge) -> some View {
        modifier(ZoomHiddenModifier(isZoomed: isZoomed, edge: edge))
    }

    func zoomable(scale: Binding<CGFloat>, contentSize: CGSize, viewport: CGRect, resetID: some Hashable,
                  onTap: @escaping () -> Void) -> some View {
        modifier(ZoomableModifier(scale: scale, contentSize: contentSize, viewport: viewport,
                                  resetID: resetID, onTap: onTap))
    }

    func trackingViewport(_ viewport: Binding<CGRect>) -> some View {
        background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    viewport.wrappedValue = newFrame
                }
        }
    }
}

func aspectFitSize(_ size: CGSize, in container: CGSize) -> CGSize {
    guard size.width > 0.0, size.height > 0.0 else { return container }
    let fit = min(container.width / size.width, container.height / size.height)
    return CGSize(width: size.width * fit, height: size.height * fit)
}
