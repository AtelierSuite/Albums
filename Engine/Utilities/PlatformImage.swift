import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

public typealias PlatformImage = UIImage
#else
import AppKit

public typealias PlatformImage = NSImage

extension NSImage {

    public convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }

    public var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    public func jpegData(compressionQuality: CGFloat) -> Data? {
        encodedData(type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: compressionQuality])
    }

    public func pngData() -> Data? {
        encodedData(type: .png, properties: [:])
    }

    public func heicData() -> Data? {
        encodedData(type: .heic, properties: [:])
    }

    private func encodedData(type: UTType, properties: [CFString: Any]) -> Data? {
        guard let cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif

extension PlatformImage {

    public func data() -> Data {
        if let data = jpegData(compressionQuality: 1.0) {
            return data
        } else if let data = pngData() {
            return data
        } else if let data = heicData() {
            return data
        }
        return Data()
    }

    public func jpegThumbnail(of length: Double) -> Data? {
        let scaleFactor = length / max(size.width, size.height)
        let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        return rendered(size: targetSize, scale: 3.0)?.jpegData(compressionQuality: 0.7)
    }

    public func scalePreservingAspectRatio(targetSize: CGSize) -> PlatformImage {
        let scaleFactor = min(targetSize.width / size.width, targetSize.height / size.height)
        let scaledImageSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        return rendered(size: scaledImageSize, scale: nil) ?? self
    }

    private func rendered(size targetSize: CGSize, scale: CGFloat?) -> PlatformImage? {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        if let scale {
            format.scale = scale
        }
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        #else
        let pixelScale = scale ?? 2.0
        let pixelWidth = max(Int((targetSize.width * pixelScale).rounded()), 1)
        let pixelHeight = max(Int((targetSize.height * pixelScale).rounded()), 1)
        guard let cgImage,
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: targetSize)
        #endif
    }
}

extension Image {
    public init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
