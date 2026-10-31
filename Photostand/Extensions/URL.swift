import Foundation

extension URL {
    static func widgetDestination(albumID: String?, libraryID: String?, picID: String? = nil) -> URL? {
        guard let albumID, picID != nil || albumID != PhotostandDatabase.rootAlbumID else { return nil }
        var components = URLComponents()
        components.scheme = "picmate"
        components.host = "album"
        components.path = "/\(albumID)"
        var queryItems: [URLQueryItem] = []
        if let libraryID {
            queryItems.append(URLQueryItem(name: "library", value: libraryID))
        }
        if let picID {
            queryItems.append(URLQueryItem(name: "pic", value: picID))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}
