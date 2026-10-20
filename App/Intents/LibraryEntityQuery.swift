import AppIntents
import Engine

extension LibraryEntity {
    static let defaultQuery = LibraryEntityQuery()

    init(library: PicLibrary) {
        self.init(id: library.id, name: Self.displayName(for: library.name))
    }

    static func orderedLibraries() async -> [PicLibrary] {
        let currentID = PicLibrary.persistedCurrentID
        return await LibrariesActor.shared.allLibraries().sorted { lhs, rhs in
            if lhs.id == currentID { return true }
            if rhs.id == currentID { return false }
            return displayName(for: lhs.name)
                .localizedCaseInsensitiveCompare(displayName(for: rhs.name)) == .orderedAscending
        }
    }
}

struct LibraryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LibraryEntity] {
        await LibraryEntity.orderedLibraries()
            .filter { identifiers.contains($0.id) }
            .map { LibraryEntity(library: $0) }
    }

    func entities(matching string: String) async throws -> [LibraryEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [LibraryEntity] {
        await LibraryEntity.orderedLibraries().map { LibraryEntity(library: $0) }
    }
}
