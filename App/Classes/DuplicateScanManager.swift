import Engine
import Foundation
import ImageIO
import SwiftUI
import UIKit

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var pics: [Pic]
}

@MainActor @Observable
class DuplicateScanManager {

    var isScanning: Bool = false
    var scanProgress: Int = 0
    var scanTotal: Int = 0
    var scanPhase: ScanPhase = .idle

    var duplicateGroups: [DuplicateGroup] = []
    var autoSelection: [UUID: Set<String>] = [:]

    var hammingThreshold: Double = 8

    let collectionID: String?

    var dataActor: DataActor {
        if let collectionID {
            return DataActor(collectionID: collectionID)
        }
        return DataActor.shared
    }

    init(collectionID: String? = nil) {
        self.collectionID = collectionID
    }

    enum ScanPhase {
        case idle
        case computingHashes
        case comparingHashes
        case done
    }

    enum ScanScope {
        case entireCollection
        case picsNotInAlbums
        case album(Album)
    }

    func scan(scope: ScanScope, autoSelect: DuplicateAutoSelectOptions = DuplicateAutoSelectOptions()) async {
        withAnimation(.smooth.speed(2.0)) {
            isScanning = true
            scanPhase = .computingHashes
        }
        scanProgress = 0
        duplicateGroups = []
        autoSelection = [:]

        let dataActor = self.dataActor
        let allScopedIDs: [String]
        switch scope {
        case .entireCollection:
            allScopedIDs = await dataActor.allPicIDs()
        case .picsNotInAlbums:
            allScopedIDs = await dataActor.picIDsNotInAnyAlbum()
        case .album(let album):
            allScopedIDs = await dataActor.picIDs(inAlbumWithID: album.id)
        }

        let cachedIDs = await HashActor.shared.picIDsWithCachedHash()
        let uncachedIDs = allScopedIDs.filter { !cachedIDs.contains($0) }

        scanTotal = uncachedIDs.count

        // Hash the synced thumbnail, not the original (which sync may evict or never download).
        for picID in uncachedIDs {
            if let data = await dataActor.thumbnailData(forPicWithID: picID),
               let image = UIImage(data: data),
               let hash = DHash.compute(from: image) {
                await HashActor.shared.storeHash(hash, forPicWithID: picID)
            }
            scanProgress += 1
        }

        scanPhase = .comparingHashes

        let allHashes = await HashActor.shared.allCachedHashes()
        let scopedIDSet = Set(allScopedIDs)
        let scopedHashes = allHashes.filter { scopedIDSet.contains($0.0) }

        let groups = findDuplicateGroups(hashes: scopedHashes, threshold: Int(hammingThreshold.rounded()))

        var resultGroups: [DuplicateGroup] = []
        for group in groups where group.count >= 2 {
            var pics: [Pic] = []
            for (picID, _) in group {
                if let pic = await dataActor.pic(forID: picID) {
                    pics.append(pic)
                }
            }
            if pics.count >= 2 {
                let sortedPics = pics.sorted { $0.dateAdded < $1.dateAdded }
                resultGroups.append(DuplicateGroup(pics: sortedPics))
            }
        }

        resultGroups.sort { groupA, groupB in
            let earliestA = groupA.pics.first?.dateAdded ?? .distantFuture
            let earliestB = groupB.pics.first?.dateAdded ?? .distantFuture
            return earliestA < earliestB
        }

        autoSelection = await autoSelection(for: resultGroups, options: autoSelect)
        duplicateGroups = resultGroups
        withAnimation(.smooth.speed(2.0)) {
            scanPhase = .done
            isScanning = false
        }
    }

    func removePics(withIDs deletedIDs: Set<String>) {
        duplicateGroups = duplicateGroups.compactMap { group in
            var updated = group
            updated.pics.removeAll { deletedIDs.contains($0.id) }
            return updated.pics.count >= 2 ? updated : nil
        }
    }

    // MARK: - Auto-Select

    private func autoSelection(
        for groups: [DuplicateGroup],
        options: DuplicateAutoSelectOptions
    ) async -> [UUID: Set<String>] {
        guard options.criterion != .none else { return [:] }
        let dataActor = self.dataActor
        var selection: [UUID: Set<String>] = [:]
        for group in groups {
            var candidates: [DuplicateCandidate] = []
            for pic in group.pics {
                var pixelCount = 0
                var fileSize: Int64 = 0
                if options.criterion.needsImageMetadata,
                   let data = await dataActor.imageData(forPicWithID: pic.id) {
                    fileSize = Int64(data.count)
                    pixelCount = Self.pixelCount(of: data)
                }
                candidates.append(DuplicateCandidate(
                    id: pic.id, date: pic.dateAdded, pixelCount: pixelCount,
                    fileSize: fileSize, isProtected: pic.isPinned
                ))
            }
            let ids = DuplicateAutoSelector.idsToSelect(from: candidates, options: options)
            if !ids.isEmpty {
                selection[group.id] = ids
            }
        }
        return selection
    }

    private static func pixelCount(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return 0
        }
        return width * height
    }

    // MARK: - Union-Find Grouping

    private func findDuplicateGroups(
        hashes: [(String, UInt64)],
        threshold: Int
    ) -> [[(String, UInt64)]] {
        let count = hashes.count
        guard count > 1 else { return [] }

        var parent = Array(0..<count)

        func find(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        func union(_ lhs: Int, _ rhs: Int) {
            let rootLHS = find(lhs)
            let rootRHS = find(rhs)
            if rootLHS != rootRHS { parent[rootLHS] = rootRHS }
        }

        for idx in 0..<count {
            for jdx in (idx + 1)..<count {
                let dist = DHash.hammingDistance(hashes[idx].1, hashes[jdx].1)
                if dist <= threshold {
                    union(idx, jdx)
                }
            }
        }

        var groups: [Int: [(String, UInt64)]] = [:]
        for idx in 0..<count {
            let root = find(idx)
            groups[root, default: []].append(hashes[idx])
        }

        return Array(groups.values.filter { $0.count >= 2 })
    }
}
