import Engine
import Foundation
import SwiftUI

enum SortConfidence: Sendable {
    case strong
    case likely
    case weak
    case none
}

struct AlbumMatch: Identifiable, Sendable {
    var albumID: String
    var albumName: String
    var distance: Float
    var confidence: SortConfidence
    var medoidPicID: String?

    var id: String { albumID }
}

struct PrintMember: Sendable {
    let picID: String
    let vector: [Float]
    let labels: [String]
}

@MainActor
@Observable
final class EntitySuggestion: Identifiable {
    let pic: Pic
    let originalAlbumID: String?
    let matches: [AlbumMatch]
    let isUnanalyzable: Bool
    var selectedAlbumID: String?

    nonisolated var id: String { pic.id }

    var topMatch: AlbumMatch? { matches.first }

    init(pic: Pic, originalAlbumID: String?, matches: [AlbumMatch],
         isUnanalyzable: Bool, selectedAlbumID: String?) {
        self.pic = pic
        self.originalAlbumID = originalAlbumID
        self.matches = matches
        self.isUnanalyzable = isUnanalyzable
        self.selectedAlbumID = selectedAlbumID
    }
}

@MainActor @Observable
class IntelligentSortManager {

    var isRunning: Bool = false
    var progress: Int = 0
    var total: Int = 0
    var phase: SortPhase = .idle

    var suggestions: [EntitySuggestion] = []
    var targetAlbumCount: Int = 0

    /// 0.0 = strict (fewer, closer matches), 1.0 = loose (more matches).
    var looseness: Double = 0.5

    var committedMoves: [CommittedMove] = []

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

    enum SortPhase {
        case idle
        case buildingAlbumModels
        case analyzingPics
        case matching
        case done
    }

    enum SortScope {
        case album(Album)
        case root
    }

    struct CommittedMove: Sendable {
        let picID: String
        let fromAlbumID: String?
        let toAlbumID: String
    }

    struct StaleAlbum {
        let album: Album
        let memberIDs: [String]
        let signature: String
    }

    // MARK: - Run

    func sort(scope: SortScope) async {
        withAnimation(.smooth.speed(2.0)) {
            isRunning = true
            phase = .buildingAlbumModels
        }
        progress = 0
        suggestions = []
        committedMoves = []

        let dataActor = self.dataActor
        let featureActor = FeaturePrintActor.instance(for: dataActor.collectionID)
        let modelActor = AlbumModelActor.instance(for: dataActor.collectionID)

        let (sourceIDs, targets) = await resolveScope(scope, dataActor: dataActor)
        targetAlbumCount = targets.count

        var (models, stale) = await scanAlbumModels(targets, dataActor: dataActor, modelActor: modelActor)
        if Task.isCancelled { return finish(cancelled: true) }

        var idsNeedingPrints = Set(sourceIDs)
        for album in stale { idsNeedingPrints.formUnion(album.memberIDs) }

        let alreadyCached = await featureActor.picIDsWithCachedPrint()
        let missing = Array(idsNeedingPrints.subtracting(alreadyCached))
        withAnimation(.smooth.speed(2.0)) {
            phase = .analyzingPics
            progress = 0
            total = missing.count
        }
        await analyzePrints(missing, using: dataActor, featureActor: featureActor)
        if Task.isCancelled { return finish(cancelled: true) }

        withAnimation(.smooth.speed(2.0)) {
            phase = .buildingAlbumModels
            progress = 0
            total = stale.count
        }
        await buildStaleModels(stale, into: &models, featureActor: featureActor, modelActor: modelActor)
        if Task.isCancelled { return finish(cancelled: true) }

        withAnimation(.smooth.speed(2.0)) { phase = .matching }
        let built = await match(sourceIDs: sourceIDs, targets: targets,
                                models: models, dataActor: dataActor, featureActor: featureActor)
        if Task.isCancelled { return finish(cancelled: true) }
        suggestions = built
        finish(cancelled: false)
    }

    private func resolveScope(
        _ scope: SortScope, dataActor: DataActor
    ) async -> (sourceIDs: [String], targets: [Album]) {
        switch scope {
        case .album(let album):
            let sources = await dataActor.picIDs(inAlbumWithID: album.id)
            let targets = await dataActor.descendantAlbums(ofAlbumWithID: album.id)
            return (sources, targets)
        case .root:
            let sources = await dataActor.picIDsNotInAnyAlbum()
            let targets = await dataActor.descendantAlbums(ofAlbumWithID: nil)
            return (sources, targets)
        }
    }

    private func scanAlbumModels(
        _ targets: [Album], dataActor: DataActor, modelActor: AlbumModelActor
    ) async -> (models: [String: AlbumModel], stale: [StaleAlbum]) {
        var models: [String: AlbumModel] = [:]
        var stale: [StaleAlbum] = []
        total = targets.count
        progress = 0
        for album in targets {
            if Task.isCancelled { break }
            let memberIDs = await dataActor.picIDs(inAlbumWithID: album.id)
            let signature = Self.signature(forPicIDs: memberIDs)
            if let cached = await modelActor.cachedModel(forAlbumWithID: album.id),
               cached.signature == signature {
                models[album.id] = cached.model
            } else if !memberIDs.isEmpty {
                stale.append(StaleAlbum(album: album, memberIDs: memberIDs, signature: signature))
            }
            progress += 1
        }
        return (models, stale)
    }

    private func buildStaleModels(
        _ stale: [StaleAlbum], into models: inout [String: AlbumModel],
        featureActor: FeaturePrintActor, modelActor: AlbumModelActor
    ) async {
        for album in stale {
            if Task.isCancelled { return }
            let stored = await featureActor.cachedPrints(forPicIDs: album.memberIDs)
            let members = album.memberIDs.compactMap { id -> PrintMember? in
                guard let print = stored[id] else { return nil }
                return PrintMember(picID: id, vector: print.vector, labels: print.labels)
            }
            if !members.isEmpty {
                let model = Self.buildAlbumModel(members: members, totalMemberCount: album.memberIDs.count)
                models[album.album.id] = model
                await modelActor.storeModel(model, signature: album.signature, forAlbumWithID: album.album.id)
            }
            progress += 1
        }
    }

    private func match(
        sourceIDs: [String], targets: [Album], models: [String: AlbumModel],
        dataActor: DataActor, featureActor: FeaturePrintActor
    ) async -> [EntitySuggestion] {
        total = sourceIDs.count
        progress = 0
        let modeledAlbums = targets.filter { models[$0.id]?.prototypes.isEmpty == false }
        var built: [EntitySuggestion] = []
        for picID in sourceIDs {
            if Task.isCancelled { return built }
            guard let pic = await dataActor.pic(forID: picID) else { progress += 1; continue }
            guard let stored = await featureActor.cachedPrint(forPicWithID: picID) else {
                built.append(EntitySuggestion(pic: pic, originalAlbumID: pic.containingAlbumID,
                                              matches: [], isUnanalyzable: true, selectedAlbumID: nil))
                progress += 1
                continue
            }
            let matches = rankedMatches(for: stored.vector, albums: modeledAlbums, models: models)
            let preselect = matches.first?.confidence == .strong
            built.append(EntitySuggestion(pic: pic, originalAlbumID: pic.containingAlbumID,
                                          matches: matches, isUnanalyzable: false,
                                          selectedAlbumID: preselect ? matches.first?.albumID : nil))
            progress += 1
        }
        return built
    }

    private func rankedMatches(
        for vector: [Float], albums: [Album], models: [String: AlbumModel]
    ) -> [AlbumMatch] {
        var matches: [AlbumMatch] = []
        for album in albums {
            guard let model = models[album.id] else { continue }
            var best = Float.greatestFiniteMagnitude
            var bestMedoid: String?
            for prototype in model.prototypes {
                let distance = EntityVision.cosineDistance(prototype.centroid, vector)
                if distance < best {
                    best = distance
                    bestMedoid = prototype.medoidPicID
                }
            }
            matches.append(AlbumMatch(albumID: album.id, albumName: album.name,
                                      distance: best, confidence: confidence(for: best),
                                      medoidPicID: bestMedoid))
        }
        matches.sort { $0.distance < $1.distance }
        return Array(matches.prefix(5))
    }

    private func finish(cancelled: Bool) {
        withAnimation(.smooth.speed(2.0)) {
            phase = cancelled ? .idle : .done
            isRunning = false
        }
    }

    // MARK: - Print computation (bounded parallelism, off-main Vision)

    /// `missing` is the already-filtered set of pics without a cached print, and
    /// `total` is set by the caller so the progress bar shows the right
    /// denominator from the first frame. Concurrency is capped one below the
    /// core count so the synchronous Vision work can't starve the executor
    /// servicing actor hops and progress updates.
    private func analyzePrints(
        _ missing: [String], using dataActor: DataActor, featureActor: FeaturePrintActor
    ) async {
        guard !missing.isEmpty else { return }

        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        await withTaskGroup(of: (String, StoredFeaturePrint?).self) { group in
            var index = 0
            func addNext() {
                guard index < missing.count else { return }
                let picID = missing[index]
                index += 1
                group.addTask(priority: .userInitiated) {
                    let data = await dataActor.thumbnailData(forPicWithID: picID)
                    let result: EntityVision.Result? = data.flatMap { bytes in
                        autoreleasepool { EntityVision.featurePrint(fromThumbnailData: bytes) }
                    }
                    guard let result else { return (picID, nil) }
                    return (picID, StoredFeaturePrint(vector: result.vector,
                                                      labels: result.labels,
                                                      visionRevision: result.visionRevision))
                }
            }
            for _ in 0..<min(limit, missing.count) { addNext() }
            while let (picID, print) = await group.next() {
                if let print {
                    await featureActor.storePrint(print.vector, labels: print.labels,
                                                  visionRevision: print.visionRevision,
                                                  forPicWithID: picID)
                }
                progress += 1
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                addNext()
            }
        }
    }

}
