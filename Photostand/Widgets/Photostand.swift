import AppIntents
import SwiftUI
import WidgetKit

struct PhotostandEntryView: SwiftUI.View {
    var entry: PhotostandProvider.Entry

    var body: some SwiftUI.View {
        Group {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                GeometryReader { geometry in
                    Image(uiImage: uiImage)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
                }
            } else {
                placeholder
            }
        }
    }

    var placeholder: some SwiftUI.View {
        VStack(spacing: 4) {
            Image(systemName: "photo.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if entry.albumID == nil {
                Text("Photostand.Placeholder.SelectAlbum", tableName: "Widgets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Photostand.Placeholder.NoPics", tableName: "Widgets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Photostand: Widget {
    let kind: String = "Photostand"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectAlbumIntent.self,
            provider: PhotostandProvider()
        ) { entry in
            PhotostandEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemGray5)
                }
                .widgetURL(widgetURL(for: entry))
        }
        .configurationDisplayName(Text("Photostand.DisplayName", tableName: "Widgets"))
        .description(Text("Photostand.Description", tableName: "Widgets"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }

    private func widgetURL(for entry: PhotostandEntry) -> URL? {
        guard let albumID = entry.albumID else { return nil }
        return URL(string: "picmate://album/\(albumID)")
    }
}
