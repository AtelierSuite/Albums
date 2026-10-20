import Foundation
@preconcurrency import SQLite
import UIKit

public struct PicOriginalReplacement: Sendable {
    public let thumbnailData: Data?
    public let albumID: String?
}

extension DataActor {

    public func replaceImageOriginal(
        forPicWithID id: String, with data: Data, isMirroredToCloud: Bool
    ) -> PicOriginalReplacement? {
        let query = picsTable
            .filter(picId == id)
            .select(picMediaType, picAlbumId, picThumbnailData)
        guard let row = try? database.pluck(query),
              (try? row.get(picMediaType)) == MediaType.pic.rawValue else { return nil }
        let albumID = (try? row.get(picAlbumId)) ?? nil
        let oldThumbnail = (try? row.get(picThumbnailData)) ?? nil

        var setters: [Setter] = []
        let existingFileURL = localImageFileURL(forPicWithID: id)
        if existingFileURL != nil || !isMirroredToCloud {
            ensureImagesDirectoryExists()
            let relativePath = "\(Self.imagesDirectoryName)/\(id)"
            let fileURL = existingFileURL ?? imageFileURL(forRelativePath: relativePath)
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                debugPrint("Failed to replace image file: \(error)")
                return nil
            }
            if existingFileURL == nil {
                setters.append(picFilePath <- relativePath)
            }
        }
        let thumbnailData = Pic.makeThumbnail(data)
        setters.append(contentsOf: [
            picThumbnailData <- thumbnailData,
            syncOriginalSynced <- isMirroredToCloud,
            syncDirty <- true,
            syncLastModified <- syncTimestamp
        ])
        do {
            try database.run(picsTable.filter(picId == id).update(setters))
        } catch {
            debugPrint("Failed to update edited pic: \(error)")
            return nil
        }
        if dataColumnExists() {
            _ = try? database.run(picsTable.filter(picId == id).update(picData <- Data()))
        }
        if let albumID {
            replaceAlbumCover(ofAlbumWithID: albumID, ifDerivedFromThumbnail: oldThumbnail, with: data)
        }
        notifyLocalMutation()
        return PicOriginalReplacement(thumbnailData: thumbnailData, albumID: albumID)
    }

    private func localImageFileURL(forPicWithID id: String) -> URL? {
        let query = picsTable.filter(picId == id).select(picFilePath)
        guard let row = try? database.pluck(query),
              let path = (try? row.get(picFilePath)) ?? nil,
              isImagePath(path) else { return nil }
        let url = imageFileURL(forRelativePath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func replaceAlbumCover(
        ofAlbumWithID albumID: String, ifDerivedFromThumbnail thumbnail: Data?, with data: Data
    ) {
        guard let thumbnail,
              let coverData = albumCoverData(forAlbumWithID: albumID),
              let coverImage = UIImage(data: coverData),
              let thumbnailImage = UIImage(data: thumbnail),
              coverImage.size.height > 0, thumbnailImage.size.height > 0 else { return }
        let coverAspect = coverImage.size.width / coverImage.size.height
        let thumbnailAspect = thumbnailImage.size.width / thumbnailImage.size.height
        guard abs(coverAspect - thumbnailAspect) < 0.02,
              let coverHash = DHash.compute(from: coverImage),
              let thumbnailHash = DHash.compute(from: thumbnailImage),
              DHash.hammingDistance(coverHash, thumbnailHash) <= 3,
              let newCover = Album.makeCover(data) else { return }
        _ = try? database.run(albumsTable.filter(albumId == albumID).update(albumCoverPhoto <- newCover))
    }
}
