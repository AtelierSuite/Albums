import AppIntents
import Engine
import UniformTypeIdentifiers

enum PicFileLoader {

    static func pics(in album: AlbumEntity, order: PicOrder) async throws -> [Pic] {
        try AppLock.ensureUnlocked()
        let model = try await album.resolvedAlbum()
        let dataActor = DataActor.instance(for: album.libraryID)
        let pics = try await dataActor.picSkeletons(in: model, order: order == .oldest ? .forward : .reverse)
            .filter { $0.mediaType == .pic }
        return order == .random ? pics.shuffled() : pics
    }

    static func files(for pics: [Pic], in libraryID: String, limit: Int) async -> [IntentFile] {
        var files: [IntentFile] = []
        for pic in pics.prefix(limit * 2 + 1) where files.count < limit {
            guard let data = await PicOriginalExporter.imageData(forPicID: pic.id, in: libraryID) else { continue }
            let fileExtension = PicOriginalExporter.imageFileExtension(for: data)
            files.append(IntentFile(
                data: data,
                filename: "\(PicOriginalExporter.filenameStem(from: pic.name)).\(fileExtension)",
                type: UTType(filenameExtension: fileExtension)
            ))
        }
        return files
    }
}
