import Foundation
@preconcurrency import SQLite
import UIKit

struct PhotostandDatabase {
    static let appGroupID = "group.com.tsubuzaki.IllustMate"

    static let albumsTable = Table("albums")
    static let picsTable = Table("pics")
    static let librariesTable = Table("collections")

    static let albumId = Expression<String>("id")
    static let albumName = Expression<String>("name")

    static let libraryId = Expression<String>("id")
    static let libraryName = Expression<String>("name")

    static let picId = Expression<String>("id")
    static let picAlbumId = Expression<String?>("containing_album_id")
    static let picData = Expression<Data?>("data")
    static let picMediaType = Expression<Int>("media_type")
    static let picFilePath = Expression<String?>("file_path")
    static let picThumbnailData = Expression<Data?>("thumbnail_data")
    static let picDateDeleted = Expression<Double?>("date_deleted")

    static let maxBlobSize = 25 * 1024 * 1024 // 25 MB

    static let ubiquityContainerID = "iCloud.com.tsubuzaki.IllustMate"
    static let defaultLibraryID = "__default__"

    struct AlbumRecord {
        let id: String
        let name: String
    }

    struct LibraryRecord {
        let id: String
        let name: String
    }

    private static func appGroupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func libraryBaseURL(forLibraryID libraryID: String) -> URL? {
        guard let base = appGroupURL() else { return nil }
        return libraryID == defaultLibraryID ? base : base.appendingPathComponent(libraryID)
    }

    static func openDatabase(forLibraryID libraryID: String = defaultLibraryID) -> Connection? {
        guard let url = libraryBaseURL(forLibraryID: libraryID)?
            .appendingPathComponent("Collection.db") else { return nil }
        return try? Connection(url.path)
    }

    private static func openLibrariesDatabase() -> Connection? {
        guard let url = appGroupURL()?.appendingPathComponent("Libraries.db") else { return nil }
        return try? Connection(url.path, readonly: true)
    }

    private static func livePicsTable(in database: Connection) -> Table {
        let columns = (try? database.prepare("PRAGMA table_info(\"pics\")"))?
            .compactMap { $0[1] as? String } ?? []
        return columns.contains("date_deleted") ? picsTable.filter(picDateDeleted == nil) : picsTable
    }

    static func fetchAllLibraries() -> [LibraryRecord] {
        let fallback = [LibraryRecord(id: defaultLibraryID, name: "")]
        guard let database = openLibrariesDatabase(),
              let rows = try? database.prepare(librariesTable.select(libraryId, libraryName)) else {
            return fallback
        }
        var records = rows.compactMap { row -> LibraryRecord? in
            guard let id = try? row.get(libraryId),
                  let name = try? row.get(libraryName) else { return nil }
            return LibraryRecord(id: id, name: name)
        }
        if !records.contains(where: { $0.id == defaultLibraryID }) {
            records.insert(LibraryRecord(id: defaultLibraryID, name: ""), at: 0)
        }
        return records
    }

    static func fetchAllAlbums(inLibraryWithID libraryID: String = defaultLibraryID) -> [AlbumRecord] {
        guard let database = openDatabase(forLibraryID: libraryID) else { return [] }
        let query = albumsTable.select(albumId, albumName).order(albumName.asc)
        guard let rows = try? database.prepare(query) else { return [] }
        return rows.compactMap { row in
            guard let id = try? row.get(albumId),
                  let name = try? row.get(albumName) else { return nil }
            return AlbumRecord(id: id, name: name)
        }
    }

    static func fetchAlbum(withID id: String, inLibraryWithID libraryID: String = defaultLibraryID) -> AlbumRecord? {
        guard let database = openDatabase(forLibraryID: libraryID) else { return nil }
        let query = albumsTable.filter(albumId == id).select(albumId, albumName)
        guard let row = try? database.pluck(query),
              let rowId = try? row.get(albumId),
              let name = try? row.get(albumName) else { return nil }
        return AlbumRecord(id: rowId, name: name)
    }

    static func fetchRandomPicData(
        inAlbumWithID albumID: String,
        inLibraryWithID libraryID: String = defaultLibraryID,
        maxDimension: CGFloat = 800
    ) -> Data? {
        guard let database = openDatabase(forLibraryID: libraryID) else { return nil }
        return fetchRandomPicData(using: database, albumID: albumID,
                                  libraryID: libraryID, maxDimension: maxDimension)
    }

    static func fetchRandomPicData(
        using database: Connection,
        albumID: String,
        libraryID: String = defaultLibraryID,
        maxDimension: CGFloat = 800
    ) -> Data? {
        let idQuery = livePicsTable(in: database)
            .filter(picAlbumId == albumID)
            .filter(picMediaType == 0)
            .select(picId)
            .order(Expression<Int>.random())
            .limit(1)
        guard let idRow = try? database.pluck(idQuery),
              let randomId = try? idRow.get(picId),
              let data = rawPicData(forID: randomId, using: database, libraryID: libraryID) else { return nil }
        return UIImage.downsampledForWidget(data: data, maxDimension: maxDimension)
    }

    static func fetchRandomPicDataMultiple(
        inAlbumWithID albumID: String,
        inLibraryWithID libraryID: String = defaultLibraryID,
        count: Int,
        maxDimension: CGFloat = 800
    ) -> [Data] {
        guard let database = openDatabase(forLibraryID: libraryID) else { return [] }
        let idQuery = livePicsTable(in: database)
            .filter(picAlbumId == albumID)
            .filter(picMediaType == 0)
            .select(picId)
            .order(Expression<Int>.random())
            .limit(count)
        guard let rows = try? database.prepare(idQuery) else { return [] }
        let ids = rows.compactMap { try? $0.get(picId) }
        return ids.compactMap { id in
            autoreleasepool {
                guard let data = rawPicData(forID: id, using: database, libraryID: libraryID) else { return nil }
                return UIImage.downsampledForWidget(data: data, maxDimension: maxDimension)
            }
        }
    }

    private static func rawPicData(forID id: String, using database: Connection, libraryID: String) -> Data? {
        let query = picsTable.filter(picId == id)
            .select(picFilePath, picMediaType, picThumbnailData)
        guard let row = try? database.pluck(query) else { return nil }
        if let path = try? row.get(picFilePath),
           let baseURL = libraryBaseURL(forLibraryID: libraryID),
           let data = cappedData(at: baseURL.appendingPathComponent(path)) {
            return data
        }
        if (try? row.get(picMediaType)) == 0, let data = ubiquityImageData(forID: id, libraryID: libraryID) {
            return data
        }
        if let blob = legacyBlob(forID: id, using: database), blob.count <= maxBlobSize {
            return blob
        }
        return try? row.get(picThumbnailData)
    }

    private static func legacyBlob(forID id: String, using database: Connection) -> Data? {
        let query = picsTable.filter(picId == id).select(picData)
        guard let blob = try? database.pluck(query).flatMap({ try? $0.get(picData) }),
              !blob.isEmpty else { return nil }
        return blob
    }

    private static func cappedData(at fileURL: URL) -> Data? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value,
              size <= Int64(maxBlobSize) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    private static func ubiquityImageData(forID id: String, libraryID: String) -> Data? {
        guard let container = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerID) else { return nil }
        let fileURL = container.appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(libraryID, isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(id)
        let status = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        if status == .current {
            return cappedData(at: fileURL)
        }
        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        return nil
    }

    static func fetchPicCount(inAlbumWithID albumID: String,
                              inLibraryWithID libraryID: String = defaultLibraryID) -> Int {
        guard let database = openDatabase(forLibraryID: libraryID) else { return 0 }
        let query = livePicsTable(in: database).filter(picAlbumId == albumID).filter(picMediaType == 0)
        return (try? database.scalar(query.count)) ?? 0
    }
}
