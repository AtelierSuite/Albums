import SwiftUI

struct PicSortPicker: View {

    @Binding var selection: PicSortType

    var body: some View {
        SortMenu(
            field: Binding {
                selection.field
            } set: {
                selection = PicSortType(field: $0, isAscending: selection.isAscending)
            },
            isAscending: Binding {
                selection.isAscending
            } set: {
                selection = PicSortType(field: selection.field, isAscending: $0)
            }
        ) {
            Text("Shared.Sort.DateAdded")
                .tag(PicSortField.dateAdded)
            Text("Shared.Sort.Name")
                .tag(PicSortField.name)
            Text("Shared.Sort.ProminentColor")
                .tag(PicSortField.prominentColor)
            Text("Shared.Sort.Size")
                .tag(PicSortField.size)
            Text("Shared.Sort.AspectRatio")
                .tag(PicSortField.aspectRatio)
        }
    }
}
