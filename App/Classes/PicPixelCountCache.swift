import AVFoundation
import Engine
import Foundation
import ImageIO

actor PicPixelCountCache {
    static let shared = PicPixelCountCache()

    private var counts: [String: Int] = [:]

    func pixelCounts(for pics: [Pic]) async -> [String: Int] {
        let uncached = pics.filter { counts[$0.id] == nil }
        if !uncached.isEmpty {
            let maxConcurrent = 8
            let computed = await withTaskGroup(of: (String, Int?).self,
                                               returning: [(String, Int)].self) { group in
                var iterator = uncached.makeIterator()
                for _ in 0..<min(maxConcurrent, uncached.count) {
                    guard let pic = iterator.next() else { break }
                    group.addTask { (pic.id, await Self.pixelCount(of: pic)) }
                }
                var results: [(String, Int)] = []
                for await (id, count) in group {
                    if let count {
                        results.append((id, count))
                    }
                    if let pic = iterator.next() {
                        group.addTask { (pic.id, await Self.pixelCount(of: pic)) }
                    }
                }
                return results
            }
            for (id, count) in computed {
                counts[id] = count
            }
        }
        return Dictionary(pics.compactMap { pic in counts[pic.id].map { (pic.id, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    private static func pixelCount(of pic: Pic) async -> Int? {
        let dataActor = DataActor.shared
        if pic.isVideo {
            guard let path = pic.filePath else { return nil }
            let asset = AVURLAsset(url: dataActor.videoFileURL(forRelativePath: path))
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize) else { return nil }
            return Int(abs(size.width) * abs(size.height))
        }
        if let path = pic.filePath, dataActor.isImagePath(path),
           let source = CGImageSourceCreateWithURL(
               dataActor.imageFileURL(forRelativePath: path) as CFURL, nil
           ),
           let count = pixelCount(of: source) {
            return count
        }
        guard let data = await dataActor.imageData(forPicWithID: pic.id),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelCount(of: source)
    }

    private static func pixelCount(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return width * height
    }
}
