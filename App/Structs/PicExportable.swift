import CoreTransferable
import Engine
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PicImageExportable: Codable, Transferable {

    var id: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .image) { exportable in
            guard let url = await PicOriginalExporter.imageFileURL(forPicID: exportable.id,
                                                                   name: exportable.name) else {
                throw PicExportError.unavailable
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName { PicOriginalExporter.suggestedImageFilename(forPicID: $0.id, name: $0.name) }
        ProxyRepresentation { (exportable: PicImageExportable) in
            PicTransferable(id: exportable.id)
        }
    }
}

struct PicVideoExportable: Codable, Transferable {

    var id: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .movie) { exportable in
            guard let url = await PicOriginalExporter.videoFileURL(forPicID: exportable.id,
                                                                   name: exportable.name) else {
                throw PicExportError.unavailable
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName { PicOriginalExporter.suggestedVideoFilename(forPicID: $0.id, name: $0.name) }
        ProxyRepresentation { (exportable: PicVideoExportable) in
            PicTransferable(id: exportable.id)
        }
    }
}

enum PicExportError: Error {
    case unavailable
}

enum PicOriginalExporter {

    static func imageData(forPicID id: String, in collectionID: String) async -> Data? {
        if let data = await DataActor.instance(for: collectionID).imageData(forPicWithID: id) {
            return data
        }
        return await OriginalsManager.shared.fetchOriginal(picID: id, in: collectionID)
    }

    static func imageFileURL(forPicID id: String, name: String) async -> URL? {
        guard let data = await imageData(forPicID: id, in: DataActor.shared.collectionID) else { return nil }
        let url = temporaryURL(base: name, ext: imageFileExtension(for: data))
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func videoFileURL(forPicID id: String, name: String) async -> URL? {
        let collectionID = DataActor.shared.collectionID
        var sourceURL = await DataActor.shared.videoURL(forPicWithID: id)
        if sourceURL == nil {
            sourceURL = await OriginalsManager.shared.materializedVideoURL(picID: id, in: collectionID)
        }
        guard let sourceURL else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let url = temporaryURL(base: name, ext: ext)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: url)
            return url
        } catch {
            return nil
        }
    }

    static func suggestedImageFilename(forPicID id: String, name: String) -> String {
        let stem = filenameStem(from: name)
        let collectionID = DataActor.shared.collectionID
        let candidates = [
            DataActor.shared.imagesDirectoryURL().appendingPathComponent(id),
            OriginalsManager.shared.cloudImageOriginalURL(forPicID: id, in: collectionID)
        ].compactMap { $0 }
        for url in candidates {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let uti = CGImageSourceGetType(source),
               let type = UTType(uti as String),
               let ext = type.preferredFilenameExtension {
                return "\(stem).\(ext)"
            }
        }
        return stem
    }

    static func suggestedVideoFilename(forPicID id: String, name: String) -> String {
        let stem = filenameStem(from: name)
        let directory = DataActor.shared.videosDirectoryURL()
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
           let match = entries.first(where: { ($0 as NSString).deletingPathExtension == id }) {
            let ext = (match as NSString).pathExtension
            if !ext.isEmpty { return "\(stem).\(ext)" }
        }
        let collectionID = DataActor.shared.collectionID
        if let ext = OriginalsManager.shared.cloudVideoOriginalExtension(forPicID: id, in: collectionID) {
            return "\(stem).\(ext)"
        }
        return stem
    }

    private static func temporaryURL(base: String, ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenameStem(from: base)).\(ext)")
        try? FileManager.default.removeItem(at: url)
        return url
    }

    static func filenameStem(from name: String) -> String {
        let trimmed = (name as NSString).deletingPathExtension
        return (trimmed.isEmpty ? name : trimmed)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func imageFileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source),
              let type = UTType(uti as String),
              let ext = type.preferredFilenameExtension else {
            return "png"
        }
        return ext
    }
}
