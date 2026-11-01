import SwiftUI

struct SortMenu<Field: Hashable, FieldOptions: View>: View {

    @Binding var field: Field
    @Binding var isAscending: Bool
    @ViewBuilder var fieldOptions: FieldOptions

    var body: some View {
        Menu("Shared.Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Shared.Sort", selection: $field) {
                fieldOptions
            }
            .pickerStyle(.inline)
            Picker("Shared.Sort.Order", selection: $isAscending) {
                Label("Shared.Sort.Ascending", systemImage: "arrow.up")
                    .tag(true)
                Label("Shared.Sort.Descending", systemImage: "arrow.down")
                    .tag(false)
            }
            .pickerStyle(.inline)
        }
    }
}
