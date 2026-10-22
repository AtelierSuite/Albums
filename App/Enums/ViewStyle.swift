import Foundation

let picViewStyleKey = "PicViewStyle"

enum ViewStyle: String {
    case grid
    case list
    case carousel
    case masonry
}

enum AlbumViewStyle: String, CaseIterable {
    case mosaicGrid = "grid.mosaic"
    case stackedGrid = "grid"
    case layeredGrid = "grid.layered"
    case plainGrid = "grid.plain"
    case stackedCarousel = "carousel"
    case plainCarousel = "carousel.plain"
    case compactCarousel = "carousel.compact"
    case list

    static let gridStyles: [AlbumViewStyle] = [.mosaicGrid, .stackedGrid, .layeredGrid, .plainGrid]
    static let carouselStyles: [AlbumViewStyle] = [.stackedCarousel, .plainCarousel, .compactCarousel]

    init(storedValue: String) {
        self = AlbumViewStyle(rawValue: storedValue) ?? .mosaicGrid
    }

    var isGrid: Bool {
        Self.gridStyles.contains(self)
    }

    var isCarousel: Bool {
        Self.carouselStyles.contains(self)
    }

    var isResizable: Bool {
        self != .list && self != .compactCarousel
    }

    var coverStyle: AlbumCoverStyle {
        switch self {
        case .mosaicGrid: .mosaic
        case .layeredGrid: .peek
        case .plainGrid, .plainCarousel: .flat()
        default: .stack
        }
    }
}
