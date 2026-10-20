import AVFoundation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

public final class Pic: Identifiable, Hashable, @unchecked Sendable {
    public var id: String
    public var name: String
    public var containingAlbumID: String?
    public var dateAdded: Date
    public var thumbnailData: Data?
    public var mediaType: MediaType
    public var duration: TimeInterval?
    public var filePath: String?
    public var dateDeleted: Date?

    public var isVideo: Bool { mediaType == .video }

    public init(id: String = UUID().uuidString, name: String, containingAlbumID: String? = nil,
                dateAdded: Date = Date.now, mediaType: MediaType = .pic,
                duration: TimeInterval? = nil, filePath: String? = nil) {
        self.id = id
        self.name = name
        self.containingAlbumID = containingAlbumID
        self.dateAdded = dateAdded
        self.mediaType = mediaType
        self.duration = duration
        self.filePath = filePath
    }

    public static func == (lhs: Pic, rhs: Pic) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public func identifiableString() -> String {
        let thumbnailSize = thumbnailData?.count ?? 0
        return "\(id)-\(thumbnailSize)"
    }

    public func thumbnail() -> UIImage? {
        if let thumbnailData {
            return UIImage(data: thumbnailData)
        }
        return nil
    }

    public static func newFilename() -> String {
        let date = Date.now
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmssSSSS"
        return "PIC_" + dateFormatter.string(from: date)
    }

    public static func makeThumbnail(_ data: Data?) -> Data? {
        if let data, let sourceImage = UIImage(data: data) {
            return sourceImage.jpegThumbnail(of: 120.0)
        }
        return nil
    }

    public static func makeVideoThumbnail(_ url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let result = try? await generator.image(at: .zero),
              case let cgImage = result.image else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }

    public static func newVideoFilename() -> String {
        let date = Date.now
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmssSSSS"
        return "VID_" + dateFormatter.string(from: date)
    }
}

public struct PicTransferable: Codable, Transferable, Sendable {

    public init(id: String) {
        self.id = id
    }

    public var id: String

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: PicTransferable.self, contentType: .picture)
    }
}

extension UTType {
    public static var picture: UTType { UTType(exportedAs: "com.tsubuzaki.IllustMate.Pic") }
}
