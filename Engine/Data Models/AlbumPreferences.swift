import Foundation

public struct AlbumPreferences: Sendable {
    public var albumID: String
    public var albumSort: String
    public var albumViewStyle: String
    public var albumColumnCount: Int
    public var picSort: String
    public var picColumnCount: Int
    public var hideSectionHeaders: Bool

    public init(
        albumID: String,
        albumSort: String,
        albumViewStyle: String,
        albumColumnCount: Int,
        picSort: String,
        picColumnCount: Int,
        hideSectionHeaders: Bool
    ) {
        self.albumID = albumID
        self.albumSort = albumSort
        self.albumViewStyle = albumViewStyle
        self.albumColumnCount = albumColumnCount
        self.picSort = picSort
        self.picColumnCount = picColumnCount
        self.hideSectionHeaders = hideSectionHeaders
    }

    public static let defaults = AlbumPreferences(
        albumID: "",
        albumSort: "nameAscending",
        albumViewStyle: "grid.mosaic",
        albumColumnCount: 4,
        picSort: "dateAddedDescending",
        picColumnCount: 4,
        hideSectionHeaders: false
    )
}
