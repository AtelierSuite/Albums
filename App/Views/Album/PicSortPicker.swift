import SwiftUI

struct PicSortPicker: View {

    @Binding var selection: PicSortType

    var body: some View {
        Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $selection) {
            Text("Shared.Sort.DateAdded.Ascending")
                .tag(PicSortType.dateAddedAscending)
            Text("Shared.Sort.DateAdded.Descending")
                .tag(PicSortType.dateAddedDescending)
            Text("Shared.Sort.Name.Ascending")
                .tag(PicSortType.nameAscending)
            Text("Shared.Sort.Name.Descending")
                .tag(PicSortType.nameDescending)
            Text("Shared.Sort.ProminentColor")
                .tag(PicSortType.prominentColor)
        }
        .pickerStyle(.menu)
    }
}
