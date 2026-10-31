import os
import WidgetKit

struct PhotostandEntry: TimelineEntry {
    let date: Date
    let albumID: String?
    let albumName: String?
    let libraryID: String?
    let pic: PhotostandDatabase.WidgetPic?
}

struct PhotostandProvider: AppIntentTimelineProvider {
    static let log = Logger(subsystem: "com.tsubuzaki.IllustMate.Photostand", category: "Timeline")

    func placeholder(in context: Context) -> PhotostandEntry {
        PhotostandEntry(date: .now, albumID: nil, albumName: nil, libraryID: nil, pic: nil)
    }

    func snapshot(for configuration: SelectAlbumIntent, in context: Context) async -> PhotostandEntry {
        guard let album = configuration.album else {
            return PhotostandEntry(date: .now, albumID: nil, albumName: nil, libraryID: nil, pic: nil)
        }
        let libraryID = configuration.library?.id ?? album.libraryID
        let maxDimension = maxDimension(for: context.family)
        let pic = PhotostandDatabase.fetchRandomPic(
            inAlbumWithID: album.id, inLibraryWithID: libraryID, maxDimension: maxDimension
        )
        return PhotostandEntry(date: .now, albumID: album.id, albumName: album.name, libraryID: libraryID, pic: pic)
    }

    func timeline(for configuration: SelectAlbumIntent, in context: Context) async -> Timeline<PhotostandEntry> {
        guard let album = configuration.album else {
            Self.log.notice("Photostand timeline: no album configured")
            let entry = PhotostandEntry(date: .now, albumID: nil, albumName: nil, libraryID: nil, pic: nil)
            return Timeline(entries: [entry], policy: .never)
        }

        let libraryID = configuration.library?.id ?? album.libraryID
        guard let database = PhotostandDatabase.openDatabase(forLibraryID: libraryID) else {
            Self.log.error("Photostand timeline: failed to open database")
            let entry = PhotostandEntry(date: .now, albumID: album.id, albumName: album.name,
                                        libraryID: libraryID, pic: nil)
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600)))
        }

        let picCount = PhotostandDatabase.fetchPicCount(inAlbumWithID: album.id, inLibraryWithID: libraryID)
        let interval = configuration.refreshInterval
        Self.log.notice("Photostand timeline: album \(album.id, privacy: .public) pics=\(picCount)")

        if picCount == 0 {
            let entry = PhotostandEntry(date: .now, albumID: album.id, albumName: album.name,
                                        libraryID: libraryID, pic: nil)
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(interval.seconds)))
        }

        let maxDim = maxDimension(for: context.family)

        var entries: [PhotostandEntry] = []
        entries.reserveCapacity(interval.entryCount)
        let currentDate = Date.now
        for entryIndex in 0..<interval.entryCount {
            let entryDate = currentDate.addingTimeInterval(interval.seconds * Double(entryIndex))
            // Use autoreleasepool so intermediate buffers are freed each iteration
            let pic: PhotostandDatabase.WidgetPic? = autoreleasepool {
                PhotostandDatabase.fetchRandomPic(
                    using: database, albumID: album.id, libraryID: libraryID, maxDimension: maxDim
                )
            }
            entries.append(PhotostandEntry(
                date: entryDate,
                albumID: album.id,
                albumName: album.name,
                libraryID: libraryID,
                pic: pic
            ))
        }

        let withImages = entries.filter { $0.pic != nil }.count
        Self.log.notice("Photostand timeline: \(entries.count) entries, \(withImages) with images")
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func maxDimension(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 400
        case .systemMedium, .systemLarge:
            return 600
        @unknown default:
            return 400
        }
    }
}
