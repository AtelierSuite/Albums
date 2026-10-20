import AppIntents
import Engine
import UIKit
import UniformTypeIdentifiers

struct SaveImagesIntent: AppIntent {
    static let title = LocalizedStringResource("SaveImages.Title", table: "Intents")
    static let description = IntentDescription(LocalizedStringResource("SaveImages.Description", table: "Intents"))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: LocalizedStringResource("Parameter.Files", table: "Intents"),
               supportedContentTypes: [.image, .movie],
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var files: [IntentFile]

    @Parameter(title: LocalizedStringResource("Parameter.Album", table: "Intents"))
    var album: AlbumEntity

    @Parameter(title: LocalizedStringResource("Parameter.SkipDuplicates", table: "Intents"), default: false)
    var skipDuplicates: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$files) to \(\.$album)", table: "Intents") {
            \.$skipDuplicates
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        _ = try await album.resolvedAlbum()
        guard let library = await LibrariesActor.shared.library(for: album.libraryID) else {
            throw IntentError.libraryNotFound
        }
        var temporaryURLs: [URL] = []
        defer {
            for url in temporaryURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        var items: [SharedItem] = []
        for file in files {
            let type = file.type ?? UTType(filenameExtension: (file.filename as NSString).pathExtension)
            if type?.conforms(to: .movie) == true {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(type?.preferredFilenameExtension ?? "mov")
                try file.data.write(to: url)
                temporaryURLs.append(url)
                items.append(.video(url))
            } else if UIImage(data: file.data) != nil {
                items.append(.image(file.data))
            }
        }
        guard !items.isEmpty else { throw IntentError.noSupportedFiles }
        if skipDuplicates {
            let destination = SaveDestination.albums(libraryID: library.id, libraryName: library.name,
                                                     albumID: album.id, albumName: album.name)
            let duplicateIndexes = Set(await DuplicateChecker.matches(for: items, in: destination).map(\.itemIndex))
            items = items.enumerated().filter { !duplicateIndexes.contains($0.offset) }.map(\.element)
        }
        if !items.isEmpty {
            do {
                try await LibrarySaver.save(items, toLibrary: library.id, albumID: album.id)
            } catch is LibrarySaver.MissingLibrary {
                throw IntentError.libraryNotFound
            } catch is LibrarySaver.MissingAlbum {
                throw IntentError.albumNotFound
            }
        }
        return .result(
            value: items.count,
            dialog: IntentDialog(LocalizedStringResource("SaveImages.Result.\(items.count)-\(album.name)",
                                                         table: "Intents"))
        )
    }
}
