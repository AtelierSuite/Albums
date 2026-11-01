import Engine
import SwiftUI

struct AlbumSortPicker: View {

    @Binding var selection: SortType

    var body: some View {
        SortMenu(
            field: Binding {
                selection.field
            } set: {
                selection = SortType(field: $0, isAscending: selection.isAscending)
            },
            isAscending: Binding {
                selection.isAscending
            } set: {
                selection = SortType(field: selection.field, isAscending: $0)
            }
        ) {
            Text("Shared.Sort.Name")
                .tag(AlbumSortField.name)
            Text("Shared.Sort.PicCount")
                .tag(AlbumSortField.picCount)
        }
    }
}

enum AlbumSortField: Hashable {
    case name
    case picCount
}

extension SortType {
    init(field: AlbumSortField, isAscending: Bool) {
        switch field {
        case .name: self = isAscending ? .nameAscending : .nameDescending
        case .picCount: self = isAscending ? .sizeAscending : .sizeDescending
        }
    }

    var field: AlbumSortField {
        switch self {
        case .nameAscending, .nameDescending: .name
        case .sizeAscending, .sizeDescending: .picCount
        }
    }

    var isAscending: Bool {
        self == .nameAscending || self == .sizeAscending
    }
}
