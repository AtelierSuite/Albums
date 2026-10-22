import SwiftUI

struct AlbumLayoutMetrics {

    static let carouselColumnRange = 2...6

    var style: AlbumViewStyle
    var containerWidth: CGFloat
    var columnCount: Int

    var gridHorizontalPadding: CGFloat {
        style == .stackedGrid ? 14.0 : 16.0
    }

    var gridColumnSpacing: CGFloat {
        style == .stackedGrid ? 10.0 : 12.0
    }

    var gridRowSpacing: CGFloat {
        style == .stackedGrid ? 12.0 : 14.0
    }

    var gridWidth: CGFloat {
        max(containerWidth - gridHorizontalPadding * 2.0, 0.0)
    }

    var gridColumnLimit: GridColumnLimit {
        GridColumnLimit(minimumCellWidth: GridColumnLimit.albums.minimumCellWidth,
                        spacing: gridColumnSpacing,
                        range: GridColumnLimit.albums.range)
    }

    var gridColumnRange: ClosedRange<Int> {
        gridColumnLimit.range(width: gridWidth)
    }

    var fittedColumnCount: Int {
        gridColumnLimit.columns(columnCount, width: gridWidth)
    }

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridColumnSpacing, alignment: .top),
              count: fittedColumnCount)
    }

    var gridCoverWidth: CGFloat {
        let count = CGFloat(fittedColumnCount)
        return (gridWidth - gridColumnSpacing * (count - 1.0)) / count
    }

    var gridLabelStyle: AlbumLabelStyle {
        AlbumLabelStyle(viewStyle: style, coverWidth: gridCoverWidth)
    }

    var carouselCoverLength: CGFloat {
        let baseLength: CGFloat = style == .plainCarousel ? 132.0 : 80.0
        return baseLength * 4.0 / CGFloat(min(max(columnCount, Self.carouselColumnRange.lowerBound),
                                              Self.carouselColumnRange.upperBound))
    }

    var carouselSpacing: CGFloat {
        style == .stackedCarousel ? 20.0 : 12.0
    }

    var carouselLabelStyle: AlbumLabelStyle {
        AlbumLabelStyle(viewStyle: style, coverWidth: carouselCoverLength)
    }
}

extension View {
    func albumCarouselPinch(columnCount: Int,
                            style: AlbumViewStyle,
                            onColumnCountChange: ((Int) -> Void)?) -> some View {
        pinchToResizeColumns(Binding {
            columnCount
        } set: { count in
            onColumnCountChange?(count)
        }, range: AlbumLayoutMetrics.carouselColumnRange,
           isEnabled: style.isResizable && onColumnCountChange != nil)
    }
}
