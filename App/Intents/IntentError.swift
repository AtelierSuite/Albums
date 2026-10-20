import AppIntents
import Foundation

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case appLocked
    case libraryNotFound
    case albumNotFound
    case noPics
    case noSupportedFiles
    case emptyAlbumName

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appLocked: LocalizedStringResource("Error.AppLocked", table: "Intents")
        case .libraryNotFound: LocalizedStringResource("Error.LibraryNotFound", table: "Intents")
        case .albumNotFound: LocalizedStringResource("Error.AlbumNotFound", table: "Intents")
        case .noPics: LocalizedStringResource("Error.NoPics", table: "Intents")
        case .noSupportedFiles: LocalizedStringResource("Error.NoSupportedFiles", table: "Intents")
        case .emptyAlbumName: LocalizedStringResource("Error.EmptyAlbumName", table: "Intents")
        }
    }
}

enum AppLock {
    static var isEnabled: Bool {
        UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")?.bool(forKey: "AppLockEnabled") ?? false
    }

    static func ensureUnlocked() throws {
        if isEnabled {
            throw IntentError.appLocked
        }
    }
}
