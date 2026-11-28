import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum WidgetImage {

    static func downsampled(data: Data, maxDimension: CGFloat = 800) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, downsampleOptions as CFDictionary
        ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func image(from data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: cgImage, scale: 1.0)
    }
}

extension Color {
    static var widgetBackground: Color {
        #if os(iOS)
        Color(.systemGray5)
        #else
        Color(nsColor: .quaternarySystemFill)
        #endif
    }
}
