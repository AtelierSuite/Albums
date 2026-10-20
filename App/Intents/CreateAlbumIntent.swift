import AppIntents
import Engine

struct CreateAlbumIntent: AppIntent {
    static let title = LocalizedStringResource("CreateAlbum.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("CreateAlbum.Description", table: "Intents"))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: LocalizedStringResource("Parameter.Name", table: "Intents"))
    var name: String

    @Parameter(title: LocalizedStringResource("Parameter.Library", table: "Intents"))
    var library: LibraryEntity?

    @Parameter(title: LocalizedStringResource("Parameter.ParentAlbum", table: "Intents"))
    var parentAlbum: AlbumEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$parentAlbum, .hasAnyValue) {
            Summary("Create \(\.$name) in \(\.$parentAlbum)", table: "Intents")
        } otherwise: {
            Summary("Create \(\.$name) in \(\.$library)", table: "Intents") {
                \.$parentAlbum
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AlbumEntity> & ProvidesDialog {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw IntentError.emptyAlbumName }
        let libraryID: String
        if let parentAlbum {
            _ = try await parentAlbum.resolvedAlbum()
            libraryID = parentAlbum.libraryID
        } else {
            libraryID = library?.id ?? PicLibrary.persistedCurrentID
        }
        guard let targetLibrary = await LibrariesActor.shared.library(for: libraryID) else {
            throw IntentError.libraryNotFound
        }
        let album = await DataActor.instance(for: libraryID)
            .createAlbum(trimmedName, parentAlbumID: parentAlbum?.id)
        let showsLibraryName = await LibrariesActor.shared.allLibraries().count > 1
        return .result(
            value: AlbumEntity(album: album, in: targetLibrary, showsLibraryName: showsLibraryName),
            dialog: IntentDialog(LocalizedStringResource("CreateAlbum.Result.\(album.name)", table: "Intents"))
        )
    }
}
