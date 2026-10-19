import CoreGraphics
import Engine
import Foundation
import UIKit

enum SampleDataGenerator {

    private struct RenderedPic: Sendable {
        let name: String
        let data: Data
        let albumID: String?
        let date: Date
    }

    static func generate(
        picCount: Int,
        albumCount: Int,
        into dataActor: DataActor,
        legacyBlobs: Bool = false,
        progress: @escaping @MainActor (_ completed: Int, _ total: Int) -> Void
    ) async {
        let albumIDs = await makeAlbums(count: albumCount, into: dataActor)
        await makePics(count: picCount, albumIDs: albumIDs, into: dataActor,
                       legacyBlobs: legacyBlobs, progress: progress)
    }

    // MARK: - Albums

    private static func makeAlbums(count: Int, into dataActor: DataActor) async -> [String] {
        var albumIDs: [String] = []
        for _ in 0..<count {
            let parent: String? = (!albumIDs.isEmpty && Double.random(in: 0..<1) < 0.35)
                ? albumIDs.randomElement()
                : nil
            let album = await dataActor.createAlbum(randomAlbumName(), parentAlbumID: parent)
            albumIDs.append(album.id)
        }
        return albumIDs
    }

    private static func randomAlbumName() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let length = Int.random(in: 4...16)
        var chars = (0..<length).map { _ in letters.randomElement() ?? "a" }
        if length > 10 && Bool.random() {
            chars.insert(" ", at: Int.random(in: 5...8))
        }
        return String(chars)
    }

    // MARK: - Pics

    private static func makePics(
        count: Int,
        albumIDs: [String],
        into dataActor: DataActor,
        legacyBlobs: Bool,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async {
        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount)
        await withTaskGroup(of: RenderedPic.self) { group in
            var submitted = 0
            while submitted < min(maxConcurrent, count) {
                let index = submitted
                group.addTask { renderPic(index: index, albumIDs: albumIDs) }
                submitted += 1
            }
            var completed = 0
            for await pic in group {
                await insert(pic, into: dataActor, legacyBlobs: legacyBlobs)
                completed += 1
                await progress(completed, count)
                if submitted < count {
                    let index = submitted
                    group.addTask { renderPic(index: index, albumIDs: albumIDs) }
                    submitted += 1
                }
            }
        }
    }

    private static func insert(_ pic: RenderedPic, into dataActor: DataActor,
                               legacyBlobs: Bool) async {
        if legacyBlobs {
            await dataActor.createImageBlobPic(pic.name, data: pic.data,
                                               inAlbumWithID: pic.albumID, dateAdded: pic.date)
        } else {
            await dataActor.createPic(pic.name, data: pic.data,
                                      inAlbumWithID: pic.albumID, dateAdded: pic.date)
        }
    }

    private static func renderPic(index: Int, albumIDs: [String]) -> RenderedPic {
        let albumID: String? = (!albumIDs.isEmpty && Double.random(in: 0..<1) < 0.80)
            ? albumIDs.randomElement()
            : nil
        let date = Date.now.addingTimeInterval(-Double.random(in: 0...(365 * 24 * 3600)))
        return RenderedPic(name: "SAMPLE_\(index)",
                           data: renderRandomImageData(),
                           albumID: albumID,
                           date: date)
    }

    // MARK: - Image rendering (Core Graphics, off-main)

    private static func renderRandomImageData() -> Data {
        let width = Int.random(in: 800...4000)
        let height = Int.random(in: 800...4000)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        drawMeshGradient(in: context, width: width, height: height, colorSpace: colorSpace)
        for _ in 0..<Int.random(in: 2...10) {
            drawRandomShape(in: context, width: width, height: height)
        }
        guard let cgImage = context.makeImage() else { return Data() }
        return UIImage(cgImage: cgImage).data()
    }

    private static func drawMeshGradient(in context: CGContext, width: Int, height: Int,
                                         colorSpace: CGColorSpace) {
        context.interpolationQuality = .high
        let layers = Int.random(in: 2...3)
        for layer in 0..<layers {
            let grid = Int.random(in: 10...20) + layer * 6
            guard let mesh = makeMeshImage(grid: grid, colorSpace: colorSpace) else { continue }
            context.setAlpha(layer == 0 ? 1.0 : CGFloat.random(in: 0.35...0.6))
            context.setBlendMode(layer == 0 ? .normal : .overlay)
            context.draw(mesh, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setAlpha(1.0)
        context.setBlendMode(.normal)
    }

    private static func makeMeshImage(grid: Int, colorSpace: CGColorSpace) -> CGImage? {
        var pixels = [UInt8]()
        pixels.reserveCapacity(grid * grid * 4)
        for _ in 0..<(grid * grid) {
            pixels.append(.random(in: 0...255))
            pixels.append(.random(in: 0...255))
            pixels.append(.random(in: 0...255))
            pixels.append(255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: grid, height: grid, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: grid * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private static func drawRandomShape(in context: CGContext, width: Int, height: Int) {
        let minDimension = CGFloat(min(width, height))
        let size = CGFloat.random(in: (minDimension * 0.1)...(minDimension * 0.5))
        let center = CGPoint(x: CGFloat.random(in: 0...CGFloat(width)),
                             y: CGFloat.random(in: 0...CGFloat(height)))
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.setFillColor(red: .random(in: 0...1), green: .random(in: 0...1),
                             blue: .random(in: 0...1), alpha: .random(in: 0.4...0.9))
        switch Int.random(in: 0...2) {
        case 0: context.fill(rect)
        case 1: context.fillEllipse(in: rect)
        default:
            context.addPath(starPath(center: center, radius: size / 2))
            context.fillPath()
        }
    }

    private static func starPath(center: CGPoint, radius: CGFloat, points: Int = 5) -> CGPath {
        let path = CGMutablePath()
        let innerRadius = radius * 0.4
        let step = CGFloat.pi / CGFloat(points)
        var angle = -CGFloat.pi / 2
        for index in 0..<(points * 2) {
            let currentRadius = index.isMultiple(of: 2) ? radius : innerRadius
            let point = CGPoint(x: center.x + cos(angle) * currentRadius,
                                y: center.y + sin(angle) * currentRadius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}
