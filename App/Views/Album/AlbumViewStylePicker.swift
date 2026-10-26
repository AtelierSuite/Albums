import SwiftUI

struct AlbumViewStylePicker: View {

    @Binding var selection: AlbumViewStyle

    var body: some View {
        Picker(String(localized: "Albums.Style", table: "Albums"),
               systemImage: "paintbrush",
               selection: $selection.animation(.smooth.speed(2.0))) {
            Section(String(localized: "Albums.Style.Section.Grid", table: "Albums")) {
                ForEach(AlbumViewStyle.gridStyles, id: \.self) { style in
                    label(for: style)
                }
            }
            Section(String(localized: "Albums.Style.Section.Carousel", table: "Albums")) {
                ForEach(AlbumViewStyle.carouselStyles, id: \.self) { style in
                    label(for: style)
                }
            }
            Section {
                label(for: .list)
            }
        }
        .pickerStyle(.menu)
    }

    func label(for style: AlbumViewStyle) -> some View {
        Text(title(for: style))
            .tag(style)
    }

    func title(for style: AlbumViewStyle) -> String {
        switch style {
        case .mosaicGrid: String(localized: "Albums.Style.Grid.Mosaic", table: "Albums")
        case .stackedGrid: String(localized: "Albums.Style.Grid.Stacked", table: "Albums")
        case .layeredGrid: String(localized: "Albums.Style.Grid.Layered", table: "Albums")
        case .plainGrid: String(localized: "Albums.Style.Grid.Plain", table: "Albums")
        case .stackedCarousel: String(localized: "Albums.Style.Carousel.Stacked", table: "Albums")
        case .plainCarousel: String(localized: "Albums.Style.Carousel.Plain", table: "Albums")
        case .compactCarousel: String(localized: "Albums.Style.Carousel.Compact", table: "Albums")
        case .list: String(localized: "Albums.Style.List", table: "Albums")
        }
    }
}
