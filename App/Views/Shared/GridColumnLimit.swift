import SwiftUI

struct GridColumnLimit {

    var minimumCellWidth: CGFloat
    var spacing: CGFloat
    var range: ClosedRange<Int>

    static let pics = GridColumnLimit(minimumCellWidth: 50.0, spacing: 2.0, range: 2...12)
    static let albums = GridColumnLimit(minimumCellWidth: 64.0, spacing: 10.0, range: 2...10)
    static let photosAlbums = GridColumnLimit(minimumCellWidth: 64.0, spacing: 20.0, range: 2...10)

    func range(width: CGFloat) -> ClosedRange<Int> {
        guard width > 0.0 else { return range }
        let fitting = Int((width + spacing) / (minimumCellWidth + spacing))
        return range.lowerBound...min(max(fitting, range.lowerBound), range.upperBound)
    }

    func columns(_ preferred: Int, width: CGFloat) -> Int {
        let range = range(width: width)
        return min(max(preferred, range.lowerBound), range.upperBound)
    }
}
