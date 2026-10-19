import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public final class Album: Identifiable, Hashable, @unchecked Sendable {
    public var id: String
    public var name: String
    public var coverPhoto: Data?
    public var hasCoverPhoto: Bool
    public var parentAlbumID: String?
    public var dateCreated: Date

    // Transient relationships (populated after fetch)
    public var childAlbums: [Album]?
    public var childPics: [Pic]?

    // Lightweight counts (populated without loading children)
    public var childAlbumCount: Int?
    public var childPicCount: Int?

    public init(id: String = UUID().uuidString, name: String, coverPhoto: Data? = nil,
                hasCoverPhoto: Bool? = nil,
                parentAlbumID: String? = nil, dateCreated: Date = Date.now) {
        self.id = id
        self.name = name
        self.coverPhoto = coverPhoto
        self.hasCoverPhoto = hasCoverPhoto ?? (coverPhoto != nil)
        self.parentAlbumID = parentAlbumID
        self.dateCreated = dateCreated
    }

    public static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.hasCoverPhoto == rhs.hasCoverPhoto
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(hasCoverPhoto)
    }

    public func identifiableString() -> String {
        "\(id)-\(hasCoverPhoto)-\(childAlbumCount ?? 0)-\(childPicCount ?? 0)"
    }

    public func albumCount() -> Int {
        return childAlbumCount ?? childAlbums?.count ?? 0
    }

    public func picCount() -> Int {
        return childPicCount ?? childPics?.count ?? 0
    }

    public func cover() -> UIImage {
        if let coverPhoto, let uiImage = UIImage(data: coverPhoto) {
            return uiImage
        }
        return UIImage(named: "Album.Generic")!
    }

    public static func makeCover(_ data: Data?) -> Data? {
        if let data, let sourceImage = UIImage(data: data) {
            return sourceImage.jpegThumbnail(of: 160.0)
        }
        return nil
    }
}

public struct AlbumTransferable: Codable, Transferable, Sendable {

    public init(id: String) {
        self.id = id
    }

    public var id: String

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: AlbumTransferable.self, contentType: .album)
    }
}

extension UTType {
    public static var album: UTType { UTType(exportedAs: "com.tsubuzaki.IllustMate.Album") }
}
