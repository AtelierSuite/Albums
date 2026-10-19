import Engine
import SwiftUI

struct GridSizePicker: View {

    enum Kind {
        case album
        case pics
    }

    @Binding var selection: Int
    var sizes: [Int]
    var kind: Kind

    var body: some View {
        Picker("Shared.GridSize",
               systemImage: "square.grid.2x2",
               selection: $selection.animation(.smooth.speed(2.0))) {
            ForEach(resolvedSizes, id: \.self) { size in
                Text(label(for: size))
                    .tag(size)
            }
        }
        .pickerStyle(.menu)
    }

    var resolvedSizes: [Int] {
        switch kind {
        case .album: sizes + [10]
        case .pics: sizes + [10, 12]
        }
    }

    func label(for size: Int) -> LocalizedStringKey {
        let key = "Shared.GridSize.\(size)"
        return LocalizedStringKey(key)
    }
}
