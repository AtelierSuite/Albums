import Engine
import Foundation
import Photos
import SwiftUI
import UIKit

struct PhotosDuplicateGroup: Identifiable {
    let id = UUID()
    var assets: [PHAsset]
}

@MainActor @Observable
class PhotosDuplicateScanManager {

    var isScanning: Bool = false
    var scanProgress: Int = 0
    var scanTotal: Int = 0
    var scanPhase: ScanPhase = .idle

    var duplicateGroups: [PhotosDuplicateGroup] = []

    var hammingThreshold: Double = 8

    enum ScanPhase {
        case idle
        case computingHashes
        case comparingHashes
        case done
    }

    // swiftlint:disable:next function_body_length
    func scan(in collection: PHAssetCollection) async {
        withAnimation(.smooth.speed(2.0)) {
            isScanning = true
            scanPhase = .computingHashes
        }
        scanProgress = 0
        duplicateGroups = []

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)

        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        let cachedIDs = await HashActor.shared.picIDsWithCachedHash()
        let uncachedAssets = assets.filter { !cachedIDs.contains($0.localIdentifier) }

        scanTotal = uncachedAssets.count

        for asset in uncachedAssets {
            if let image = await loadImage(for: asset),
               let hash = DHash.compute(from: image) {
                await HashActor.shared.storeHash(hash, forPicWithID: asset.localIdentifier)
            }
            scanProgress += 1
        }

        withAnimation(.smooth.speed(2.0)) {
            scanPhase = .comparingHashes
        }

        let allHashes = await HashActor.shared.allCachedHashes()
        let scopedIDSet = Set(assets.map(\.localIdentifier))
        let scopedHashes = allHashes.filter { scopedIDSet.contains($0.0) }

        let groups = findDuplicateGroups(hashes: scopedHashes, threshold: Int(hammingThreshold.rounded()))

        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })

        var resultGroups: [PhotosDuplicateGroup] = []
        for group in groups where group.count >= 2 {
            var groupAssets: [PHAsset] = []
            for (assetID, _) in group {
                if let asset = assetsByID[assetID] {
                    groupAssets.append(asset)
                }
            }
            if groupAssets.count >= 2 {
                let sorted = groupAssets.sorted {
                    ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
                }
                resultGroups.append(PhotosDuplicateGroup(assets: sorted))
            }
        }

        resultGroups.sort { groupA, groupB in
            let earliestA = groupA.assets.first?.creationDate ?? .distantFuture
            let earliestB = groupB.assets.first?.creationDate ?? .distantFuture
            return earliestA < earliestB
        }

        duplicateGroups = resultGroups
        withAnimation(.smooth.speed(2.0)) {
            scanPhase = .done
            isScanning = false
        }
    }

    func removeAssets(withIDs deletedIDs: Set<String>) {
        duplicateGroups = duplicateGroups.compactMap { group in
            var updated = group
            updated.assets.removeAll { deletedIDs.contains($0.localIdentifier) }
            return updated.assets.count >= 2 ? updated : nil
        }
    }

    // MARK: - Image Loading

    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHCachingImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
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
