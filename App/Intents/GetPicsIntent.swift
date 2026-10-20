import AppIntents

struct GetPicsIntent: AppIntent {
    static let title = LocalizedStringResource("GetPics.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("GetPics.Description", table: "Intents"))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: LocalizedStringResource("Parameter.Album", table: "Intents"))
    var album: AlbumEntity

    @Parameter(title: LocalizedStringResource("Parameter.Limit", table: "Intents"),
               default: 10, inclusiveRange: (1, 100))
    var limit: Int

    @Parameter(title: LocalizedStringResource("Parameter.Order", table: "Intents"), default: .newest)
    var order: PicOrder

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$limit) pics from \(\.$album)", table: "Intents") {
            \.$order
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let pics = try await PicFileLoader.pics(in: album, order: order)
        let files = await PicFileLoader.files(for: pics, in: album.libraryID, limit: limit)
        guard !files.isEmpty else { throw IntentError.noPics }
        return .result(value: files)
    }
}
