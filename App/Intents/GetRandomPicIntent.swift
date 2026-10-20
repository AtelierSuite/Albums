import AppIntents

struct GetRandomPicIntent: AppIntent {
    static let title = LocalizedStringResource("GetRandomPic.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("GetRandomPic.Description", table: "Intents"))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: LocalizedStringResource("Parameter.Album", table: "Intents"))
    var album: AlbumEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get a random pic from ${album}", table: "Intents")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let pics = try await PicFileLoader.pics(in: album, order: .random)
        let files = await PicFileLoader.files(for: pics, in: album.libraryID, limit: 1)
        guard let file = files.first else { throw IntentError.noPics }
        return .result(value: file)
    }
}
