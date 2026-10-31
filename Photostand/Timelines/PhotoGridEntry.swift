import os
import WidgetKit

struct PhotoGridEntry: TimelineEntry {
    let date: Date
    let albumID: String?
    let albumName: String?
    let libraryID: String?
    let pics: [PhotostandDatabase.WidgetPic]
    let columns: Int
    let rows: Int
}

struct PhotoGridProvider: AppIntentTimelineProvider {
    static let log = Logger(subsystem: "com.tsubuzaki.IllustMate.Photostand", category: "Timeline")

    func placeholder(in context: Context) -> PhotoGridEntry {
        let (columns, rows) = gridSize(for: context.family)
        return PhotoGridEntry(date: .now, albumID: nil, albumName: nil, libraryID: nil, pics: [],
                              columns: columns, rows: rows)
    }

    func snapshot(for configuration: SelectAlbumForGridIntent, in context: Context) async -> PhotoGridEntry {
        let (columns, rows) = gridSize(for: context.family)
        guard let album = configuration.album else {
            return PhotoGridEntry(date: .now, albumID: nil, albumName: nil, libraryID: nil, pics: [],
                              columns: columns, rows: rows)
        }
        let libraryID = configuration.library?.id ?? album.libraryID
        let count = columns * rows
        let maxDim = gridMaxDimension(for: context.family)
        let pics = PhotostandDatabase.fetchRandomPics(
            inAlbumWithID: album.id, inLibraryWithID: libraryID, count: count, maxDimension: maxDim
        )
        return PhotoGridEntry(
            date: .now,
            albumID: album.id,
            albumName: album.name,
            libraryID: libraryID,
            pics: pics,
            columns: columns,
            rows: rows
        )
    }

    func timeline(for configuration: SelectAlbumForGridIntent, in context: Context) async -> Timeline<PhotoGridEntry> {
        let (columns, rows) = gridSize(for: context.family)
        guard let album = configuration.album else {
            Self.log.notice("PhotoGrid timeline: no album configured")
            let entry = PhotoGridEntry(
                date: .now,
                albumID: nil,
                albumName: nil,
                libraryID: nil,
                pics: [],
                columns: columns,
                rows: rows
            )
            return Timeline(entries: [entry], policy: .never)
        }

        let libraryID = configuration.library?.id ?? album.libraryID
        let count = columns * rows
        let picCount = PhotostandDatabase.fetchPicCount(inAlbumWithID: album.id, inLibraryWithID: libraryID)
        Self.log.notice("PhotoGrid timeline: album \(album.id, privacy: .public) pics=\(picCount) need=\(count)")

        if picCount == 0 {
            let entry = PhotoGridEntry(
                date: .now,
                albumID: album.id,
                albumName: album.name,
                libraryID: libraryID,
                pics: [],
                columns: columns,
                rows: rows
            )
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(86400)))
        }

        let maxDim = gridMaxDimension(for: context.family)

        // Single entry refreshed every 24 hours to stay within memory limits
        let pics: [PhotostandDatabase.WidgetPic] = autoreleasepool {
            PhotostandDatabase.fetchRandomPics(
                inAlbumWithID: album.id, inLibraryWithID: libraryID, count: count, maxDimension: maxDim
            )
        }
        Self.log.notice("PhotoGrid timeline: fetched \(pics.count) image(s) for \(album.id, privacy: .public)")
        let entry = PhotoGridEntry(
            date: .now,
            albumID: album.id,
            albumName: album.name,
            libraryID: libraryID,
            pics: pics,
            columns: columns,
            rows: rows
        )

        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(86400)))
    }

    private func gridSize(for family: WidgetFamily) -> (columns: Int, rows: Int) {
        switch family {
        case .systemSmall:
            return (2, 2)
        case .systemMedium:
            return (4, 2)
        case .systemLarge:
            return (3, 3)
        @unknown default:
            return (2, 2)
        }
    }

    /// Grid cells are much smaller than full widgets, so use smaller dimensions.
    private func gridMaxDimension(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 200
        case .systemMedium:
            return 300
        case .systemLarge:
            return 350
        @unknown default:
            return 200
        }
    }
}
