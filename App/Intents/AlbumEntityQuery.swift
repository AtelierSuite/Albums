import AppIntents
import Engine

extension AlbumEntity {
    static let defaultQuery = AlbumEntityQuery()

    init(album: Album, in library: PicLibrary, showsLibraryName: Bool) {
        self.init(id: album.id, libraryID: library.id, name: album.name,
                  libraryName: showsLibraryName ? LibraryEntity.displayName(for: library.name) : nil)
    }

    func resolvedAlbum() async throws -> Album {
        guard await LibrariesActor.shared.library(for: libraryID) != nil else {
            throw IntentError.libraryNotFound
        }
        guard let album = await DataActor.instance(for: libraryID).album(for: id) else {
            throw IntentError.albumNotFound
        }
        return album
    }
}

struct AlbumEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        let libraries = await LibraryEntity.orderedLibraries()
        var entities: [AlbumEntity] = []
        for identifier in identifiers {
            for library in libraries {
                if let album = await DataActor.instance(for: library.id).album(for: identifier) {
                    entities.append(AlbumEntity(album: album, in: library, showsLibraryName: libraries.count > 1))
                    break
                }
            }
        }
        return entities
    }

    func entities(matching string: String) async throws -> [AlbumEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [AlbumEntity] {
        let libraries = await LibraryEntity.orderedLibraries()
        var entities: [AlbumEntity] = []
        for library in libraries {
            let libraryName = libraries.count > 1 ? LibraryEntity.displayName(for: library.name) : nil
            for album in await DataActor.instance(for: library.id).albumNames() {
                entities.append(AlbumEntity(id: album.id, libraryID: library.id,
                                            name: album.name, libraryName: libraryName))
            }
        }
        return entities
    }
}
