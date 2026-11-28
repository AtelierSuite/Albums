import Engine
import Accelerate
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
import Vision

enum EntityVision {

    struct Result: Sendable {
        let vector: [Float]
        let labels: [String]
        let visionRevision: Int
    }

    static let saliencyAreaCropThreshold: CGFloat = 0.6
    static let saliencyMinimumConfidence: Float = 0.5
    static let minimumCropFloor: CGFloat = 64.0

    static func featurePrint(fromThumbnailData data: Data) -> Result? {
        guard let image = PlatformImage(data: data), let cgImage = image.cgImage else { return nil }
        return featurePrint(from: cgImage)
    }

    static func featurePrint(from cgImage: CGImage) -> Result? {
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let printRequest = VNGenerateImageFeaturePrintRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([saliencyRequest, printRequest])

        // The common case (full-bleed art) needs no crop, so the print computed
        // alongside saliency above is reused; only crop-worthy subjects pay for a
        // second feature-print pass.
        if let cropped = cropForSalientSubject(cgImage, using: saliencyRequest.results?.first) {
            let cropHandler = VNImageRequestHandler(cgImage: cropped, options: [:])
            let cropPrintRequest = VNGenerateImageFeaturePrintRequest()
            if (try? cropHandler.perform([cropPrintRequest])) != nil,
               let cropObservation = cropPrintRequest.results?.first {
                let cropVector = floats(from: cropObservation)
                if !cropVector.isEmpty {
                    return Result(vector: cropVector, labels: [],
                                  visionRevision: cropPrintRequest.revision)
                }
            }
        }

        guard let observation = printRequest.results?.first else { return nil }
        let vector = floats(from: observation)
        guard !vector.isEmpty else { return nil }
        return Result(vector: vector, labels: [], visionRevision: printRequest.revision)
    }

    // MARK: - Saliency crop

    private static func cropForSalientSubject(
        _ cgImage: CGImage, using observation: VNSaliencyImageObservation?
    ) -> CGImage? {
        guard let salientObject = observation?.salientObjects?.max(by: { $0.confidence < $1.confidence }),
              salientObject.confidence >= saliencyMinimumConfidence else {
            return nil
        }

        let box = salientObject.boundingBox
        guard box.width > 0, box.height > 0,
              box.width * box.height < saliencyAreaCropThreshold else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: box.minX * width,
            y: (1.0 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        ).integral

        guard min(cropRect.width, cropRect.height) >= minimumCropFloor,
              let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return cropped
    }

    // MARK: - Vector extraction

    private static func floats(from observation: VNFeaturePrintObservation) -> [Float] {
        let count = observation.elementCount
        let data = observation.data
        switch observation.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return [] }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return [] }
            return data.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Double.self).prefix(count).map { Float($0) }
            }
        default:
            return []
        }
    }

    // MARK: - Similarity

    static func cosineDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 2.0 }

        var dot: Float = 0
        var normLHS: Float = 0
        var normRHS: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &dot, vDSP_Length(count))
        vDSP_svesq(lhs, 1, &normLHS, vDSP_Length(count))
        vDSP_svesq(rhs, 1, &normRHS, vDSP_Length(count))

        let denominator = (normLHS.squareRoot() * normRHS.squareRoot())
        guard denominator > 0 else { return 2.0 }
        let similarity = dot / denominator
        return 1.0 - max(-1.0, min(1.0, similarity))
    }

    static func mean(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        let length = first.count
        var accumulator = [Float](repeating: 0, count: length)
        var validCount: Float = 0
        for vector in vectors where vector.count == length {
            vDSP_vadd(accumulator, 1, vector, 1, &accumulator, 1, vDSP_Length(length))
            validCount += 1
        }
        guard validCount > 0 else { return [] }
        var divisor = validCount
        vDSP_vsdiv(accumulator, 1, &divisor, &accumulator, 1, vDSP_Length(length))
        return accumulator
    }
}
