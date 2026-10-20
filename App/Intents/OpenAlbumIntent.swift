import AppIntents
import Engine

struct OpenAlbumIntent: AppIntent {
    static let title = LocalizedStringResource("OpenAlbum.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("OpenAlbum.Description", table: "Intents"))
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: LocalizedStringResource("Parameter.Album", table: "Intents"))
    var album: AlbumEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open ${album}", table: "Intents")
    }

    init() {}

    init(album: AlbumEntity) {
        self.album = album
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await album.resolvedAlbum()
        IntentNavigator.shared.open(.album(id: album.id, libraryID: album.libraryID))
        return .result()
    }
}
