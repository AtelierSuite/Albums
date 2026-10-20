import AVFoundation
import Foundation

public enum LibrarySaver {

    public struct MissingLibrary: Error {}
    public struct MissingAlbum: Error {}

    public static func save(_ items: [SharedItem], toLibrary libraryID: String, albumID: String?) async throws {
        guard await LibrariesActor.shared.library(for: libraryID) != nil else {
            throw MissingLibrary()
        }
        let dataActor = DataActor.instance(for: libraryID)
        if let albumID, await dataActor.album(for: albumID) == nil {
            throw MissingAlbum()
        }
        for item in items {
            switch item {
            case .image(let data):
                await dataActor.createPic(Pic.newFilename(), data: data, inAlbumWithID: albumID)
            case .video(let url):
                guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { continue }
                let duration = (try? await AVURLAsset(url: url).load(.duration))?.seconds ?? 0
                let fileExtension = url.pathExtension.lowercased()
                await dataActor.createVideo(
                    url.lastPathComponent,
                    data: data,
                    duration: duration,
                    fileExtension: fileExtension.isEmpty ? "mov" : fileExtension,
                    inAlbumWithID: albumID
                )
            }
        }
    }
}
