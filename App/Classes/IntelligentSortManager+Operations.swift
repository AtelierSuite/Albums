import Engine
import Foundation

extension IntelligentSortManager {

    // MARK: - Confidence

    func confidence(for distance: Float) -> SortConfidence {
        let scale = Float(0.6 + looseness * 0.8)
        if distance <= 0.20 * scale { return .strong }
        if distance <= 0.35 * scale { return .likely }
        if distance <= 0.50 * scale { return .weak }
        return .none
    }

    // MARK: - Commit / Undo

    var pendingMoveCount: Int {
        suggestions.filter { suggestion in
            guard let destination = suggestion.selectedAlbumID else { return false }
            return destination != suggestion.originalAlbumID
        }.count
    }

    var pendingDestinationCount: Int {
        Set(suggestions.compactMap { suggestion -> String? in
            guard let destination = suggestion.selectedAlbumID,
                  destination != suggestion.originalAlbumID else { return nil }
            return destination
        }).count
    }

    func acceptAllStrongMatches() {
        for suggestion in suggestions {
            if let top = suggestion.topMatch, top.confidence == .strong {
                suggestion.selectedAlbumID = top.albumID
            }
        }
    }

    func deselectAll() {
        for suggestion in suggestions {
            suggestion.selectedAlbumID = nil
        }
    }

    func commit() async {
        let dataActor = self.dataActor
        var moves: [CommittedMove] = []
        for suggestion in suggestions {
            guard let destination = suggestion.selectedAlbumID,
                  destination != suggestion.originalAlbumID else { continue }
            await dataActor.addPic(withID: suggestion.pic.id, toAlbumWithID: destination)
            moves.append(CommittedMove(picID: suggestion.pic.id,
                                       fromAlbumID: suggestion.originalAlbumID,
                                       toAlbumID: destination))
        }
        committedMoves = moves
    }

    /// Reverses a committed set of moves. Captured into the toast so undo
    /// outlives the sort sheet and its manager.
    nonisolated static func revert(_ moves: [CommittedMove], collectionID: String?) async {
        let dataActor = collectionID.map { DataActor.instance(for: $0) } ?? DataActor.shared
        for move in moves {
            if let from = move.fromAlbumID {
                await dataActor.addPic(withID: move.picID, toAlbumWithID: from)
            } else {
                await dataActor.removeParentAlbum(forPicsWithIDs: [move.picID])
            }
        }
    }

    nonisolated static func moveSummaryMessage(
        for moves: [CommittedMove], collectionID: String?
    ) async -> String {
        let count = moves.count
        let destinations = Set(moves.map { $0.toAlbumID })
        if destinations.count == 1, let albumID = destinations.first {
            let dataActor = collectionID.map { DataActor.instance(for: $0) } ?? DataActor.shared
            let name = await dataActor.album(for: albumID)?.name ?? ""
            return String(localized: "Toast.MovedToAlbum.\(count)-\(name)", table: "Photos")
        }
        return String(localized: "Toast.MovedToAlbums.\(count)-\(destinations.count)", table: "Photos")
    }

    // MARK: - Pure model building

    nonisolated static func buildAlbumModel(
        members: [PrintMember],
        totalMemberCount: Int,
        maxPrototypes: Int = 5,
        mergeThreshold: Float = 0.30
    ) -> AlbumModel {
        var centroids: [[Float]] = []
        var clusterMembers: [[(String, [Float])]] = []
        var clusterLabels: [[String: Int]] = []

        for member in members {
            let (bestIndex, bestDistance) = nearestCluster(to: member.vector, centroids: centroids)
            let canCreateNew = centroids.count < maxPrototypes
            if bestIndex >= 0, bestDistance < mergeThreshold || !canCreateNew {
                clusterMembers[bestIndex].append((member.picID, member.vector))
                centroids[bestIndex] = EntityVision.mean(of: clusterMembers[bestIndex].map { $0.1 })
                for label in member.labels { clusterLabels[bestIndex][label, default: 0] += 1 }
            } else {
                centroids.append(member.vector)
                clusterMembers.append([(member.picID, member.vector)])
                var labelCounts: [String: Int] = [:]
                for label in member.labels { labelCounts[label, default: 0] += 1 }
                clusterLabels.append(labelCounts)
            }
        }

        let prototypes = centroids.indices.map { index in
            prototype(centroid: centroids[index],
                      members: clusterMembers[index],
                      labelCounts: clusterLabels[index])
        }
        return AlbumModel(prototypes: prototypes,
                          memberCount: totalMemberCount,
                          limitedData: totalMemberCount < 3)
    }

    private nonisolated static func nearestCluster(
        to vector: [Float], centroids: [[Float]]
    ) -> (index: Int, distance: Float) {
        var bestIndex = -1
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, centroid) in centroids.enumerated() {
            let distance = EntityVision.cosineDistance(centroid, vector)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return (bestIndex, bestDistance)
    }

    private nonisolated static func prototype(
        centroid: [Float], members: [(String, [Float])], labelCounts: [String: Int]
    ) -> EntityPrototype {
        var medoidID = members.first?.0 ?? ""
        var medoidDistance = Float.greatestFiniteMagnitude
        for (id, vector) in members {
            let distance = EntityVision.cosineDistance(centroid, vector)
            if distance < medoidDistance {
                medoidDistance = distance
                medoidID = id
            }
        }
        let labels = labelCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        return EntityPrototype(centroid: centroid, medoidPicID: medoidID,
                               memberCount: members.count, labels: labels)
    }

    /// Deterministic across launches (FNV-1a), unlike `Hasher`.
    nonisolated static func signature(forPicIDs ids: [String]) -> String {
        let joined = ids.sorted().joined(separator: ",")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "\(ids.count)-\(String(hash, radix: 16))"
    }
}
