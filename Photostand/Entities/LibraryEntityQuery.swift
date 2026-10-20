import AppIntents
import WidgetKit

extension LibraryEntity {
    static let defaultQuery = LibraryEntityQuery()

    static func entity(from record: PhotostandDatabase.LibraryRecord) -> LibraryEntity {
        LibraryEntity(id: record.id, name: displayName(for: record.name))
    }
}

struct LibraryEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LibraryEntity] {
        PhotostandDatabase.fetchAllLibraries()
            .filter { identifiers.contains($0.id) }
            .map { LibraryEntity.entity(from: $0) }
    }

    func suggestedEntities() async throws -> [LibraryEntity] {
        sorted(PhotostandDatabase.fetchAllLibraries()).map { LibraryEntity.entity(from: $0) }
    }

    private func sorted(_ records: [PhotostandDatabase.LibraryRecord]) -> [PhotostandDatabase.LibraryRecord] {
        records.sorted { lhs, rhs in
            if lhs.id == PhotostandDatabase.defaultLibraryID { return true }
            if rhs.id == PhotostandDatabase.defaultLibraryID { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
