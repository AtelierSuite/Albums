import SwiftUI

struct PicViewStylePicker: View {

    @Binding var selection: ViewStyle

    var body: some View {
        Picker(String(localized: "Albums.Style", table: "Albums"),
               systemImage: "paintbrush",
               selection: $selection.animation(.smooth.speed(2.0))) {
            Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                  systemImage: "square.grid.2x2")
                .tag(ViewStyle.grid)
            Label(String(localized: "Albums.Style.Masonry", table: "Albums"),
                  systemImage: "rectangle.3.offgrid")
                .tag(ViewStyle.masonry)
        }
        .pickerStyle(.menu)
    }
}
