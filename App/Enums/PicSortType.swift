import Foundation

enum PicSortField: Hashable {
    case dateAdded
    case name
    case prominentColor
}

enum PicSortType: String {
    case dateAddedAscending
    case dateAddedDescending
    case nameAscending
    case nameDescending
    case prominentColor
    case prominentColorDescending

    init(field: PicSortField, isAscending: Bool) {
        switch field {
        case .dateAdded: self = isAscending ? .dateAddedAscending : .dateAddedDescending
        case .name: self = isAscending ? .nameAscending : .nameDescending
        case .prominentColor: self = isAscending ? .prominentColor : .prominentColorDescending
        }
    }

    var field: PicSortField {
        switch self {
        case .dateAddedAscending, .dateAddedDescending: .dateAdded
        case .nameAscending, .nameDescending: .name
        case .prominentColor, .prominentColorDescending: .prominentColor
        }
    }

    var isAscending: Bool {
        switch self {
        case .dateAddedAscending, .nameAscending, .prominentColor: true
        default: false
        }
    }
}
