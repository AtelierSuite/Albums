import Engine
import SwiftUI

struct GridSizePicker: View {

    @Binding var selection: Int
    var sizes: [Int]

    var body: some View {
        Picker("Shared.GridSize",
               systemImage: "square.grid.2x2",
               selection: $selection.animation(.smooth.speed(2.0))) {
            ForEach(sizes + (UIDevice.current.userInterfaceIdiom == .phone ? [] : [10]), id: \.self) { size in
                Text(label(for: size))
                    .tag(size)
            }
        }
        .pickerStyle(.menu)
    }

    func label(for size: Int) -> LocalizedStringKey {
        let key = "Shared.GridSize.\(size)"
        return LocalizedStringKey(key)
    }
}
