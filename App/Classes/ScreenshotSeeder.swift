#if DEBUG
import Engine
import UIKit

enum ScreenshotSeeder {

    private struct Manifest: Decodable {
        let libraries: [Library]
        let titles: [String: String]?
    }

    private struct Library: Decodable {
        let `default`: Bool?
        let name: String?
        let sync: Bool?
        let cover: [String]?
        let albums: [Album]
        let pics: [String]
    }

    private struct Album: Decodable {
        let name: String
        let pics: [String]
        let albums: [Album]?
    }

    private struct Seeding {
        let seedURL: URL
        let titles: [String: String]
        var dateAdded = Date(timeIntervalSince1970: 1_791_100_000)

        func title(for name: String) -> String {
            let parts = name.split(separator: "~").map(String.init)
            let title = titles[parts[0]] ?? parts[0]
            return parts.count > 1 ? "\(title) 2" : title
        }

        mutating func seed(_ library: Library) async {
            let libraryID: String
            if library.default == true {
                libraryID = PicLibrary.defaultID
            } else {
                libraryID = await LibrariesActor.shared.createLibrary(name: library.name ?? "").id
            }
            let dataActor = DataActor.instance(for: libraryID)
            if await dataActor.isLibraryV2MigrationComplete() {
                await LibrariesActor.shared.setLibraryMigrated(true, forID: libraryID)
            }
            if library.sync == true {
                await LibrariesActor.shared.setSyncEnabled(true, forID: libraryID)
            }
            for album in library.albums {
                await seed(album, parentID: nil, into: dataActor)
            }
            for pic in library.pics {
                await addPic(pic, albumID: nil, into: dataActor)
            }
            if let cover = library.cover {
                let pics = (try? await dataActor.allPicSkeletons()) ?? []
                let coverIDs = cover.compactMap { name in pics.first { $0.name == title(for: name) }?.id }
                await LibrariesActor.shared.setCoverPicIDs(coverIDs, forID: libraryID)
            }
        }

        private mutating func seed(_ album: Album, parentID: String?, into dataActor: DataActor) async {
            let created = await dataActor.createAlbum(album.name, parentAlbumID: parentID)
            for child in album.albums ?? [] {
                await seed(child, parentID: created.id, into: dataActor)
            }
            for pic in album.pics {
                await addPic(pic, albumID: created.id, into: dataActor)
            }
        }

        private mutating func addPic(_ name: String, albumID: String?, into dataActor: DataActor) async {
            guard let data = try? Data(contentsOf: seedURL.appendingPathComponent("\(name).jpg")) else { return }
            await dataActor.createPic(title(for: name), data: data, inAlbumWithID: albumID, dateAdded: dateAdded)
            dateAdded = dateAdded.addingTimeInterval(-3_600)
        }
    }

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: "ScreenshotMode")
    }

    @MainActor
    static func fixWindowSize() {
        #if targetEnvironment(macCatalyst)
        let size = CGSize(width: 1280, height: 800)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = size
            scene.sizeRestrictions?.maximumSize = size
        }
        #endif
    }

    static func resetNavigation() {
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        defaults?.set(PicLibrary.defaultID, forKey: "CurrentCollectionID")
        defaults?.set(false, forKey: "PhotosModeEnabled")
        defaults?.removeObject(forKey: "LastLibraryLocation")
        defaults?.removeObject(forKey: "LastAlbumID")
    }

    static func seedIfNeeded() async -> Bool {
        let seedURL = URL.documentsDirectory.appendingPathComponent("ScreenshotSeed")
        guard let data = try? Data(contentsOf: seedURL.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return false }
        var seeding = Seeding(seedURL: seedURL, titles: manifest.titles ?? [:])
        for library in manifest.libraries {
            await seeding.seed(library)
        }
        try? FileManager.default.removeItem(at: seedURL)
        return true
    }
}
#endif
