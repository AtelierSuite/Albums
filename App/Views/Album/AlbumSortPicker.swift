import Engine
import SwiftUI

struct AlbumSortPicker: View {

    @Binding var selection: SortType

    var body: some View {
        Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $selection) {
            Text("Shared.Sort.Name.Ascending")
                .tag(SortType.nameAscending)
            Text("Shared.Sort.Name.Descending")
                .tag(SortType.nameDescending)
            Text("Shared.Sort.PicCount.Ascending")
                .tag(SortType.sizeAscending)
            Text("Shared.Sort.PicCount.Descending")
                .tag(SortType.sizeDescending)
        }
        .pickerStyle(.menu)
    }
}
