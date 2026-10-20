import Photos
import UIKit

public struct DuplicateMatch: Identifiable, Sendable {
    public let id: Int
    public let itemIndex: Int
    public let incomingThumbnail: Data?
    public let existingThumbnail: Data?
    public let location: String
}

public enum DuplicateChecker {

    static let threshold = 8

    public static func matches(for items: [SharedItem], in destination: SaveDestination,
                               timeBudget: Duration = .seconds(3)) async -> [DuplicateMatch] {
        let incoming: [Incoming] = items.enumerated().compactMap { index, item in
            guard let data = item.imageData,
                  let thumbnail = Pic.makeThumbnail(data),
                  let image = UIImage(data: thumbnail),
                  let hash = DHash.compute(from: image) else { return nil }
            return Incoming(index: index, hash: hash, thumbnail: thumbnail)
        }
        guard !incoming.isEmpty else { return [] }
        let deadline = ContinuousClock.now.advanced(by: timeBudget)
        let existing: [Candidate]
        switch destination {
        case .albums(let libraryID, _, _, _):
            existing = await libraryCandidates(libraryID: libraryID, deadline: deadline)
        case .photos(let collectionIDs, _):
            existing = await photosCandidates(collectionIDs: collectionIDs, deadline: deadline)
        }
        var matches: [DuplicateMatch] = []
        for item in incoming {
            let closest = existing
                .map { ($0, DHash.hammingDistance($0.hash, item.hash)) }
                .filter { $0.1 <= threshold }
                .min { $0.1 < $1.1 }
            guard let candidate = closest?.0 else { continue }
            matches.append(DuplicateMatch(
                id: matches.count,
                itemIndex: item.index,
                incomingThumbnail: item.thumbnail,
                existingThumbnail: await candidate.thumbnail(),
                location: candidate.location
            ))
        }
        return matches
    }

    private struct Incoming {
        let index: Int
        let hash: UInt64
        let thumbnail: Data
    }

    private struct Candidate: Sendable {
        let hash: UInt64
        let location: String
        let thumbnail: @Sendable () async -> Data?
    }

    private static func libraryCandidates(libraryID: String, deadline: ContinuousClock.Instant) async -> [Candidate] {
        guard await LibrariesActor.shared.library(for: libraryID) != nil else { return [] }
        let dataActor = DataActor.instance(for: libraryID)
        let hashActor = HashActor.instance(for: libraryID)
        var hashes = Dictionary(await hashActor.allCachedHashes(), uniquingKeysWith: { first, _ in first })
        let picAlbumIDs = await dataActor.picAlbumIDs()
        for (picID, _) in picAlbumIDs where hashes[picID] == nil {
            guard ContinuousClock.now < deadline else { break }
            if let data = await dataActor.thumbnailData(forPicWithID: picID),
               let image = UIImage(data: data),
               let hash = DHash.compute(from: image) {
                hashes[picID] = hash
                await hashActor.storeHash(hash, forPicWithID: picID)
            }
        }
        var albumNames: [String: String] = [:]
        var candidates: [Candidate] = []
        for (picID, albumID) in picAlbumIDs {
            guard let hash = hashes[picID] else { continue }
            var location = String(localized: "Destination.Collection", table: "Saving", bundle: .engine)
            if let albumID {
                if albumNames[albumID] == nil {
                    albumNames[albumID] = await dataActor.album(for: albumID)?.name
                }
                location = albumNames[albumID] ?? location
            }
            candidates.append(Candidate(hash: hash, location: location) {
                await dataActor.thumbnailData(forPicWithID: picID)
            })
        }
        return candidates
    }

    private static func photosCandidates(
        collectionIDs: [String], deadline: ContinuousClock.Instant
    ) async -> [Candidate] {
        guard await PhotosSaver.authorize() else { return [] }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: collectionIDs, options: nil)
        var candidates: [Candidate] = []
        var seen: Set<String> = []
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var assetsByCollection: [(String, [String])] = []
        collections.enumerateObjects { collection, _, _ in
            var identifiers: [String] = []
            PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
                identifiers.append(asset.localIdentifier)
            }
            assetsByCollection.append((collection.localizedTitle ?? "", identifiers))
        }
        for (title, identifiers) in assetsByCollection {
            for identifier in identifiers where !seen.contains(identifier) {
                guard ContinuousClock.now < deadline else { return candidates }
                seen.insert(identifier)
                guard let thumbnail = await PhotosSaver.localThumbnailData(forAssetWithIdentifier: identifier,
                                                                           length: 120),
                      let image = UIImage(data: thumbnail),
                      let hash = DHash.compute(from: image) else { continue }
                candidates.append(Candidate(hash: hash, location: title) { thumbnail })
            }
        }
        return candidates
    }
}
