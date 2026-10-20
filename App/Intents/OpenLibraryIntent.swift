import AppIntents
import Engine

struct OpenLibraryIntent: AppIntent {
    static let title = LocalizedStringResource("OpenLibrary.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("OpenLibrary.Description", table: "Intents"))
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: LocalizedStringResource("Parameter.Library", table: "Intents"))
    var library: LibraryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$library)", table: "Intents")
    }

    init() {}

    init(library: LibraryEntity) {
        self.library = library
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await LibrariesActor.shared.library(for: library.id) != nil else {
            throw IntentError.libraryNotFound
        }
        IntentNavigator.shared.open(.library(id: library.id))
        return .result()
    }
}
