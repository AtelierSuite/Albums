import AppIntents
import SwiftUI
import WidgetKit

struct PhotoGridEntryView: SwiftUI.View {
    var entry: PhotoGridProvider.Entry

    var body: some SwiftUI.View {
        Group {
            if entry.pics.isEmpty {
                gridPlaceholder
            } else {
                GeometryReader { geometry in
                    let cellWidth = geometry.size.width / CGFloat(entry.columns)
                    let cellHeight = geometry.size.height / CGFloat(entry.rows)

                    VStack(spacing: 0) {
                        ForEach(0..<entry.rows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<entry.columns, id: \.self) { col in
                                    let index = row * entry.columns + col
                                    if index < entry.pics.count,
                                       let uiImage = UIImage(data: entry.pics[index].imageData) {
                                        cell(for: entry.pics[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .widgetAccentedRenderingMode(.fullColor)
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: cellWidth, height: cellHeight, alignment: .top)
                                                .clipped()
                                        }
                                    } else {
                                        Color.clear
                                            .frame(width: cellWidth, height: cellHeight)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func cell(for pic: PhotostandDatabase.WidgetPic,
              @ViewBuilder content: () -> some SwiftUI.View) -> some SwiftUI.View {
        if let url = URL.widgetDestination(albumID: entry.albumID, libraryID: entry.libraryID, picID: pic.id) {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }

    var gridPlaceholder: some SwiftUI.View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if entry.albumID == nil {
                Text("PhotoGrid.Placeholder.SelectAlbum", tableName: "Widgets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("PhotoGrid.Placeholder.NoPics", tableName: "Widgets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PhotoGrid: Widget {
    let kind: String = "PhotoGrid"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectAlbumForGridIntent.self,
            provider: PhotoGridProvider()
        ) { entry in
            PhotoGridEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemGray5)
                }
                .widgetURL(URL.widgetDestination(albumID: entry.albumID, libraryID: entry.libraryID))
        }
        .configurationDisplayName(Text("PhotoGrid.DisplayName", tableName: "Widgets"))
        .description(Text("PhotoGrid.Description", tableName: "Widgets"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
