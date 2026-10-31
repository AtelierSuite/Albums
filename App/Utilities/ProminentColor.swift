import Engine
import UIKit

enum ProminentColor {

    /// Calculates the primary, accent, and contrasting colors from thumbnail image data.
    /// Primary is the most prominent color overall; accent is the most prominent
    /// higher-saturation color that isn't the primary; contrasting is the next one after it.
    static func calculate(from thumbnailData: Data) -> PicColors? {
        guard let image = UIImage(data: thumbnailData),
              let cgImage = image.cgImage else { return nil }

        // Downsample to a small size for fast processing
        let sampleSize = 32
        let width = sampleSize
        let height = sampleSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Quantize to 8 levels per channel (512 buckets)
        let shift = 5
        let bucketCount = 8 * 8 * 8
        var bucketCounts = [Int](repeating: 0, count: bucketCount)
        var bucketSumR = [Int](repeating: 0, count: bucketCount)
        var bucketSumG = [Int](repeating: 0, count: bucketCount)
        var bucketSumB = [Int](repeating: 0, count: bucketCount)

        let pixelCount = width * height
        for idx in 0..<pixelCount {
            let offset = idx * bytesPerPixel
            let red = Int(pixelData[offset])
            let green = Int(pixelData[offset + 1])
            let blue = Int(pixelData[offset + 2])
            let alpha = Int(pixelData[offset + 3])

            // Skip transparent pixels
            guard alpha > 128 else { continue }

            let bucketR = red >> shift
            let bucketG = green >> shift
            let bucketB = blue >> shift
            let bucketIndex = bucketR * 64 + bucketG * 8 + bucketB

            bucketCounts[bucketIndex] += 1
            bucketSumR[bucketIndex] += red
            bucketSumG[bucketIndex] += green
            bucketSumB[bucketIndex] += blue
        }

        let averageColor: (Int) -> Engine.RGBColor = { bucket in
            let count = bucketCounts[bucket]
            return Engine.RGBColor(red: bucketSumR[bucket] / count,
                                   green: bucketSumG[bucket] / count,
                                   blue: bucketSumB[bucket] / count)
        }

        // Primary: the most populated bucket overall
        var primaryBucket = -1
        var primaryCount = 0
        for idx in 0..<bucketCount where bucketCounts[idx] > primaryCount {
            primaryCount = bucketCounts[idx]
            primaryBucket = idx
        }

        guard primaryBucket >= 0 else {
            let gray = Engine.RGBColor(red: 128, green: 128, blue: 128)
            return PicColors(primary: gray, accent: gray, contrasting: gray)
        }

        let primary = averageColor(primaryBucket)

        // Accent and contrasting: the most populated higher-saturation buckets
        // that aren't the primary, in descending order of prominence.
        let saturationThreshold = 0.35
        var saturatedBuckets: [(bucket: Int, count: Int)] = []
        for idx in 0..<bucketCount where idx != primaryBucket && bucketCounts[idx] > 0 {
            if averageColor(idx).saturation >= saturationThreshold {
                saturatedBuckets.append((bucket: idx, count: bucketCounts[idx]))
            }
        }
        saturatedBuckets.sort { $0.count > $1.count }

        let accent = saturatedBuckets.first.map { averageColor($0.bucket) } ?? primary
        let contrasting = saturatedBuckets.count > 1
            ? averageColor(saturatedBuckets[1].bucket)
            : accent

        return PicColors(primary: primary, accent: accent, contrasting: contrasting)
    }
}
