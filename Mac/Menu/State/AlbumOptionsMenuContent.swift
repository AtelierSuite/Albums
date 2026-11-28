import Engine
import SwiftUI

struct AlbumOptionsMenuContent: View {

    enum Kind {
        case albums
        case pics
    }

    let kind: Kind

    var body: some View {
        if let options = MacMenuState.shared.album?.options {
            switch kind {
            case .albums:
                AlbumViewStylePicker(selection: options.albumStyle)
                AlbumSortPicker(selection: options.albumSort)
            case .pics:
                Picker(String(localized: "Albums.Style", table: "Albums"),
                       selection: options.picStyle.animation(.smooth.speed(2.0))) {
                    Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                          systemImage: "square.grid.2x2")
                        .tag(ViewStyle.grid)
                    Label(String(localized: "Albums.Style.Masonry", table: "Albums"),
                          systemImage: "rectangle.3.offgrid")
                        .tag(ViewStyle.masonry)
                }
                PicSortPicker(selection: options.picSort)
            }
        }
    }
}
