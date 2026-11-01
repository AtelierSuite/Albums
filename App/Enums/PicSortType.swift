import Foundation

enum PicSortField: Hashable {
    case dateAdded
    case name
    case prominentColor
    case size
    case aspectRatio
}

enum PicSortType: String {
    case dateAddedAscending
    case dateAddedDescending
    case nameAscending
    case nameDescending
    case prominentColor
    case prominentColorDescending
    case sizeAscending
    case sizeDescending
    case aspectRatioAscending
    case aspectRatioDescending

    init(field: PicSortField, isAscending: Bool) {
        switch field {
        case .dateAdded: self = isAscending ? .dateAddedAscending : .dateAddedDescending
        case .name: self = isAscending ? .nameAscending : .nameDescending
        case .prominentColor: self = isAscending ? .prominentColor : .prominentColorDescending
        case .size: self = isAscending ? .sizeAscending : .sizeDescending
        case .aspectRatio: self = isAscending ? .aspectRatioAscending : .aspectRatioDescending
        }
    }

    var field: PicSortField {
        switch self {
        case .dateAddedAscending, .dateAddedDescending: .dateAdded
        case .nameAscending, .nameDescending: .name
        case .prominentColor, .prominentColorDescending: .prominentColor
        case .sizeAscending, .sizeDescending: .size
        case .aspectRatioAscending, .aspectRatioDescending: .aspectRatio
        }
    }

    var isAscending: Bool {
        switch self {
        case .dateAddedAscending, .nameAscending, .prominentColor, .sizeAscending, .aspectRatioAscending: true
        default: false
        }
    }
}
