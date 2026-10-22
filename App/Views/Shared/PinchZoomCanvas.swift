import SwiftUI
import UIKit

struct PinchZoomCanvas: UIViewRepresentable {

    var session: PinchZoomSession
    var progress: CGFloat
    var focusY: CGFloat
    var cachedImage: (Int) -> UIImage?
    var loadImage: (Int) async -> UIImage?

    func makeUIView(context: Context) -> PinchZoomCanvasView {
        PinchZoomCanvasView()
    }

    func updateUIView(_ view: PinchZoomCanvasView, context: Context) {
        view.cachedImage = cachedImage
        view.loadImage = loadImage
        view.update(session: session, progress: progress, focusY: focusY)
    }
}

final class PinchZoomCanvasView: UIView {

    var cachedImage: (Int) -> UIImage? = { _ in nil }
    var loadImage: (Int) async -> UIImage? = { _ in nil }

    private var cells: [Int: CALayer] = [:]
    private var ghosts: [Int: CALayer] = [:]
    private var reusable: [CALayer] = []
    private var images: [Int: CGImage] = [:]
    private var requested: Set<Int> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(session: PinchZoomSession, progress: CGFloat, focusY: CGFloat) {
        let morph = session.morph(progress: progress)
        let fewerItems = session.visibleItems(columns: morph.fewerColumns, morph: morph, focusY: focusY)
        let moreItems = session.visibleItems(columns: morph.moreColumns, morph: morph, focusY: focusY)
        let items = min(fewerItems.lowerBound, moreItems.lowerBound)..<max(fewerItems.upperBound, moreItems.upperBound)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in Array(cells.keys) where !items.contains(index) {
            recycle(cells.removeValue(forKey: index))
        }
        for index in Array(ghosts.keys) where !items.contains(index) {
            recycle(ghosts.removeValue(forKey: index))
        }
        let size = CGSize(width: morph.cellWidth, height: morph.cellWidth)
        for index in items {
            let start = session.cellOrigin(index: index, columns: morph.fewerColumns, morph: morph, focusY: focusY)
            let end = session.cellOrigin(index: index, columns: morph.moreColumns, morph: morph, focusY: focusY)
            let cell = cells[index] ?? makeLayer(for: index)
            cells[index] = cell
            if abs(end.x - start.x) > morph.pitch * 1.5 {
                let ghost = ghosts[index] ?? makeLayer(for: index)
                ghosts[index] = ghost
                cell.frame = CGRect(origin: start, size: size)
                cell.opacity = Float(1.0 - morph.blend)
                ghost.frame = CGRect(origin: end, size: size)
                ghost.opacity = Float(morph.blend)
            } else {
                recycle(ghosts.removeValue(forKey: index))
                cell.frame = CGRect(origin: CGPoint(x: start.x + (end.x - start.x) * morph.blend,
                                                    y: start.y + (end.y - start.y) * morph.blend),
                                    size: size)
                cell.opacity = 1.0
            }
        }
        CATransaction.commit()
    }

    private func makeLayer(for index: Int) -> CALayer {
        let layer = reusable.popLast() ?? CALayer()
        layer.cornerRadius = 4.0
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.contentsGravity = .resizeAspectFill
        layer.backgroundColor = UIColor.label.withAlphaComponent(0.05).resolvedColor(with: traitCollection).cgColor
        layer.contents = image(for: index)
        if layer.superlayer == nil {
            self.layer.addSublayer(layer)
        }
        layer.isHidden = false
        return layer
    }

    private func recycle(_ layer: CALayer?) {
        guard let layer else { return }
        layer.isHidden = true
        layer.contents = nil
        reusable.append(layer)
    }

    private func image(for index: Int) -> CGImage? {
        if let image = images[index] {
            return image
        }
        if let image = cachedImage(index)?.cgImage {
            images[index] = image
            return image
        }
        guard !requested.contains(index) else { return nil }
        requested.insert(index)
        let loadImage = loadImage
        Task {
            guard let image = await loadImage(index)?.cgImage else { return }
            images[index] = image
            cells[index]?.contents = image
            ghosts[index]?.contents = image
        }
        return nil
    }
}
