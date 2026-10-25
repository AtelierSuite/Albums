import Foundation
import SwiftUI

enum DuplicateAutoSelectCriterion: String, CaseIterable, Identifiable, Sendable {
    case none
    case keepOldest
    case keepNewest
    case keepHighestResolution
    case keepLargestFile

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .none: LocalizedStringResource("Duplicates.AutoSelect.None", table: "Photos")
        case .keepOldest: LocalizedStringResource("Duplicates.AutoSelect.KeepOldest", table: "Photos")
        case .keepNewest: LocalizedStringResource("Duplicates.AutoSelect.KeepNewest", table: "Photos")
        case .keepHighestResolution:
            LocalizedStringResource("Duplicates.AutoSelect.KeepHighestResolution", table: "Photos")
        case .keepLargestFile: LocalizedStringResource("Duplicates.AutoSelect.KeepLargestFile", table: "Photos")
        }
    }

    var needsImageMetadata: Bool {
        self == .keepHighestResolution || self == .keepLargestFile
    }
}

struct DuplicateAutoSelectOptions: Sendable {
    var criterion: DuplicateAutoSelectCriterion = .none
    var prefersProtected: Bool = true
}

struct DuplicateCandidate: Sendable {
    let id: String
    let date: Date
    let pixelCount: Int
    let fileSize: Int64
    let isProtected: Bool
}

enum DuplicateAutoSelector {

    static func idsToSelect(
        from candidates: [DuplicateCandidate],
        options: DuplicateAutoSelectOptions
    ) -> Set<String> {
        guard options.criterion != .none, candidates.count >= 2 else { return [] }
        let protected = candidates.filter(\.isProtected)
        let pool = options.prefersProtected && !protected.isEmpty ? protected : candidates
        guard let keeper = pool.min(by: { ranksHigher($0, than: $1, criterion: options.criterion) }) else {
            return []
        }
        return Set(candidates.filter { candidate in
            candidate.id != keeper.id && !(options.prefersProtected && candidate.isProtected)
        }.map(\.id))
    }

    private static func ranksHigher(
        _ lhs: DuplicateCandidate,
        than rhs: DuplicateCandidate,
        criterion: DuplicateAutoSelectCriterion
    ) -> Bool {
        let comparisons: [(DuplicateCandidate, DuplicateCandidate) -> ComparisonResult] = {
            let byResolution: (DuplicateCandidate, DuplicateCandidate) -> ComparisonResult = {
                compare($1.pixelCount, $0.pixelCount)
            }
            let byFileSize: (DuplicateCandidate, DuplicateCandidate) -> ComparisonResult = {
                compare($1.fileSize, $0.fileSize)
            }
            let byOldest: (DuplicateCandidate, DuplicateCandidate) -> ComparisonResult = {
                compare($0.date, $1.date)
            }
            let byNewest: (DuplicateCandidate, DuplicateCandidate) -> ComparisonResult = {
                compare($1.date, $0.date)
            }
            switch criterion {
            case .none, .keepOldest: return [byOldest, byResolution, byFileSize]
            case .keepNewest: return [byNewest, byResolution, byFileSize]
            case .keepHighestResolution: return [byResolution, byFileSize, byOldest]
            case .keepLargestFile: return [byFileSize, byResolution, byOldest]
            }
        }()
        for comparison in comparisons {
            switch comparison(lhs, rhs) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        return lhs.id < rhs.id
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}
