import Foundation

public enum SaveDestination: Codable, Sendable, Equatable {
    case albums(libraryID: String, libraryName: String, albumID: String?, albumName: String?)
    case photos(collectionIDs: [String], titles: [String])

    public var title: String {
        switch self {
        case .albums(let libraryID, let libraryName, _, let albumName):
            let library = libraryID == PicLibrary.defaultID || libraryName.isEmpty
                ? String(localized: "Destination.Collection", table: "Saving", bundle: .engine)
                : libraryName
            return albumName ?? library
        case .photos(_, let titles):
            if titles.isEmpty {
                return String(localized: "Destination.PhotosLibrary", table: "Saving", bundle: .engine)
            }
            return titles.formatted(.list(type: .and))
        }
    }

    public var appName: String {
        switch self {
        case .albums: String(localized: "Destination.Albums", table: "Saving", bundle: .engine)
        case .photos: String(localized: "Destination.Photos", table: "Saving", bundle: .engine)
        }
    }

    public var systemImage: String {
        switch self {
        case .albums: "rectangle.stack.fill"
        case .photos: "photo.on.rectangle.angled"
        }
    }
}

public enum LastUsedDestination {

    private static let key = "LastUsedSaveDestination"
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
    }

    public static var current: SaveDestination? {
        get {
            guard let data = defaults?.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(SaveDestination.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
    }
}

private final class EngineBundleToken {}

extension Bundle {
    static let engine = Bundle(for: EngineBundleToken.self)
}
