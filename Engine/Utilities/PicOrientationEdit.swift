import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PicOrientationEdit: Sendable, Hashable {

    public var quarterTurns: Int
    public var isMirrored: Bool

    public init(quarterTurns: Int = 0, isMirrored: Bool = false) {
        self.quarterTurns = quarterTurns
        self.isMirrored = isMirrored
    }

    public static let identity = PicOrientationEdit()

    public var normalized: PicOrientationEdit {
        PicOrientationEdit(quarterTurns: ((quarterTurns % 4) + 4) % 4, isMirrored: isMirrored)
    }

    public var isIdentity: Bool { normalized == .identity }

    public var swapsDimensions: Bool { normalized.quarterTurns % 2 == 1 }

    public func rotatedCounterClockwise() -> PicOrientationEdit {
        PicOrientationEdit(quarterTurns: quarterTurns + (isMirrored ? -1 : 1), isMirrored: isMirrored)
    }

    public func flippedHorizontally() -> PicOrientationEdit {
        PicOrientationEdit(quarterTurns: quarterTurns, isMirrored: !isMirrored)
    }

    public func applied(after other: PicOrientationEdit) -> PicOrientationEdit {
        let turns = other.quarterTurns + (other.isMirrored ? -quarterTurns : quarterTurns)
        return PicOrientationEdit(quarterTurns: turns, isMirrored: isMirrored != other.isMirrored).normalized
    }

    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self.init(quarterTurns: 0, isMirrored: false)
        case .upMirrored: self.init(quarterTurns: 0, isMirrored: true)
        case .down: self.init(quarterTurns: 2, isMirrored: false)
        case .downMirrored: self.init(quarterTurns: 2, isMirrored: true)
        case .leftMirrored: self.init(quarterTurns: 3, isMirrored: true)
        case .right: self.init(quarterTurns: 3, isMirrored: false)
        case .rightMirrored: self.init(quarterTurns: 1, isMirrored: true)
        case .left: self.init(quarterTurns: 1, isMirrored: false)
        @unknown default: self.init()
        }
    }

    var propertyOrientation: CGImagePropertyOrientation {
        let all: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left
        ]
        return all.first { PicOrientationEdit($0) == normalized } ?? .up
    }
}

public enum PicOrientationEditor {

    static let losslessOrientationTypes: Set<String> = [
        UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier
    ]

    public static func apply(_ edit: PicOrientationEdit, to data: Data) -> Data? {
        let edit = edit.normalized
        guard !edit.isIdentity else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let currentOrientation = (properties[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let target = edit.applied(after: PicOrientationEdit(currentOrientation))
        if losslessOrientationTypes.contains(type as String),
           let rewritten = rewritingOrientation(of: source, type: type, to: target.propertyOrientation),
           isValid(rewritten, expectedOrientation: target.propertyOrientation, sourceProperties: properties) {
            return rewritten
        }
        return redrawing(source, type: type, properties: properties, applying: target)
    }

    private static func rewritingOrientation(
        of source: CGImageSource, type: CFString, to orientation: CGImagePropertyOrientation
    ) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationOrientation: orientation.rawValue,
            kCGImageDestinationMergeMetadata: true
        ]
        // CGImageDestinationCopyImageSource finalizes the destination itself; calling
        // CGImageDestinationFinalize afterwards is an error.
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else {
            return nil
        }
        return output as Data
    }

    private static func isValid(
        _ data: Data, expectedOrientation: CGImagePropertyOrientation, sourceProperties: [CFString: Any]
    ) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        return orientation == expectedOrientation.rawValue
            && width == sourceProperties[kCGImagePropertyPixelWidth] as? Int
            && height == sourceProperties[kCGImagePropertyPixelHeight] as? Int
    }

    private static func redrawing(
        _ source: CGImageSource, type: CFString, properties: [CFString: Any], applying transform: PicOrientationEdit
    ) -> Data? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let transformed = transformedImage(image, applying: transform) else { return nil }
        var outputProperties = properties
        outputProperties[kCGImagePropertyOrientation] = CGImagePropertyOrientation.up.rawValue
        if var tiff = outputProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = CGImagePropertyOrientation.up.rawValue
            outputProperties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = transformed.width
            exif[kCGImagePropertyExifPixelYDimension] = transformed.height
            outputProperties[kCGImagePropertyExifDictionary] = exif
        }
        outputProperties[kCGImagePropertyPixelWidth] = nil
        outputProperties[kCGImagePropertyPixelHeight] = nil
        outputProperties[kCGImageDestinationLossyCompressionQuality] = 0.92
        let output = NSMutableData()
        let outputType = encodableType(for: type, image: transformed)
        guard let destination = CGImageDestinationCreateWithData(output, outputType, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, transformed, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func encodableType(for type: CFString, image: CGImage) -> CFString {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        if supported.contains(type as String) { return type }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        return (hasAlpha ? UTType.png : UTType.jpeg).identifier as CFString
    }

    static func transformedImage(_ image: CGImage, applying transform: PicOrientationEdit) -> CGImage? {
        let transform = transform.normalized
        let width = image.width
        let height = image.height
        let outputWidth = transform.swapsDimensions ? height : width
        let outputHeight = transform.swapsDimensions ? width : height
        let context = makeContext(matching: image, width: outputWidth, height: outputHeight)
        guard let context else { return nil }
        let rotations: [(cos: CGFloat, sin: CGFloat)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let rotation = rotations[transform.quarterTurns]
        var affine = CGAffineTransform(a: rotation.cos, b: rotation.sin,
                                       c: -rotation.sin, d: rotation.cos, tx: 0, ty: 0)
        if transform.isMirrored {
            affine = affine.concatenating(CGAffineTransform(scaleX: -1, y: 1))
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height).applying(affine)
        affine = affine.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        context.interpolationQuality = .none
        context.concatenate(affine)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func makeContext(matching image: CGImage, width: Int, height: Int) -> CGContext? {
        let sourceSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
        if let sourceSpace,
           let context = CGContext(data: nil, width: width, height: height,
                                   bitsPerComponent: image.bitsPerComponent, bytesPerRow: 0,
                                   space: sourceSpace, bitmapInfo: image.bitmapInfo.rawValue) {
            return context
        }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        let rgbSpace = sourceSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let rgbSpace else { return nil }
        let bitsPerComponent = image.bitsPerComponent > 8 ? 16 : 8
        return CGContext(data: nil, width: width, height: height,
                         bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
                         space: rgbSpace, bitmapInfo: alphaInfo.rawValue)
    }
}
