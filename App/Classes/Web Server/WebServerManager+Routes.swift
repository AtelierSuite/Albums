import Engine
import Foundation
import UIKit

extension WebServerManager {

    // swiftlint:disable:next cyclomatic_complexity
    func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path
        let components = path.split(separator: "/").map(String.init)

        if request.method == "GET" {
            if components.first != "api" {
                // Serve the single-page app for the root and all client-side routes
                // (e.g. /{albumId}/{albumId}/...), which resolve navigation in the browser.
                return serveMainPage()
            }
            if components == ["api", "albums"] {
                return await handleGetRootAlbums()
            }
            if components.count == 3 && components[0] == "api" && components[1] == "albums" {
                return await handleGetAlbum(id: components[2])
            }
            if components == ["api", "pics"] {
                let page = Self.pagination(from: request)
                return await handleGetRootPics(offset: page.offset, limit: page.limit)
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "albums" && components[3] == "pics" {
                let page = Self.pagination(from: request)
                return await handleGetAlbumPics(id: components[2], offset: page.offset, limit: page.limit)
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "albums" && components[3] == "cover" {
                return await handleGetAlbumCover(id: components[2])
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "pics" && components[3] == "thumbnail" {
                return await handleGetPicThumbnail(id: components[2])
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "pics" && components[3] == "image" {
                return await handleGetPicImage(id: components[2])
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "pics" && components[3] == "video" {
                return await handleGetPicVideo(id: components[2], rangeHeader: request.headers["range"])
            }
        }

        if request.method == "POST" {
            if components == ["api", "upload"] {
                return await handleUploadToRoot(request: request)
            }
            if components.count == 4 && components[0] == "api" &&
                components[1] == "albums" && components[3] == "upload" {
                return await handleUploadToAlbum(id: components[2], request: request)
            }
        }

        return .notFound()
    }

    // MARK: - Pagination

    /// Default number of pics returned per page when listing an album.
    static let picPageSize = 60
    /// Upper bound on a client-requested page size.
    static let maxPicPageSize = 200

    private static func pagination(from request: HTTPRequest) -> (offset: Int, limit: Int) {
        let offset = max(Int(request.queryParameters["offset"] ?? "") ?? 0, 0)
        let requestedLimit = Int(request.queryParameters["limit"] ?? "") ?? picPageSize
        let limit = min(max(requestedLimit, 1), maxPicPageSize)
        return (offset, limit)
    }

    // MARK: - Album Routes

    private func handleGetRootAlbums() async -> HTTPResponse {
        do {
            let albums = try await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)
            let pics = try await DataActor.shared.picSkeletons(
                in: nil, order: .reverse, limit: Self.picPageSize, offset: 0
            )
            let picCount = await DataActor.shared.picCount(in: nil)
            let json: [String: Any] = [
                "name": "Collection",
                "albums": albums.map { Self.albumToJSON($0) },
                "pics": pics.map { Self.picToJSON($0) },
                "picCount": picCount
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            return .ok(json: data)
        } catch {
            return .internalError(error.localizedDescription)
        }
    }

    private func handleGetAlbum(id: String) async -> HTTPResponse {
        guard let album = await DataActor.shared.album(for: id) else {
            return .notFound()
        }
        do {
            let childAlbums = try await DataActor.shared.albumsWithCounts(in: album, sortedBy: .nameAscending)
            let pics = try await DataActor.shared.picSkeletons(
                in: album, order: .reverse, limit: Self.picPageSize, offset: 0
            )
            let picCount = await DataActor.shared.picCount(in: album)
            let path = await DataActor.shared.albumPath(forAlbumWithID: album.id)
            let json: [String: Any] = [
                "id": album.id,
                "name": album.name,
                "hasCover": album.hasCoverPhoto,
                "albums": childAlbums.map { Self.albumToJSON($0) },
                "pics": pics.map { Self.picToJSON($0) },
                "picCount": picCount,
                "path": path.map { ["id": $0.id, "name": $0.name] }
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            return .ok(json: data)
        } catch {
            return .internalError(error.localizedDescription)
        }
    }

    // MARK: - Paginated Pic Routes

    private func handleGetRootPics(offset: Int, limit: Int) async -> HTTPResponse {
        await picsPage(in: nil, offset: offset, limit: limit)
    }

    private func handleGetAlbumPics(id: String, offset: Int, limit: Int) async -> HTTPResponse {
        guard let album = await DataActor.shared.album(for: id) else {
            return .notFound()
        }
        return await picsPage(in: album, offset: offset, limit: limit)
    }

    private func picsPage(in album: Album?, offset: Int, limit: Int) async -> HTTPResponse {
        do {
            let pics = try await DataActor.shared.picSkeletons(
                in: album, order: .reverse, limit: limit, offset: offset
            )
            let json: [String: Any] = ["pics": pics.map { Self.picToJSON($0) }]
            let data = try JSONSerialization.data(withJSONObject: json)
            return .ok(json: data)
        } catch {
            return .internalError(error.localizedDescription)
        }
    }

    // MARK: - Image Routes

    private func handleGetAlbumCover(id: String) async -> HTTPResponse {
        guard let album = await DataActor.shared.album(for: id) else {
            return .notFound()
        }
        if let coverData = album.coverPhoto {
            return .ok(imageData: coverData, contentType: "image/jpeg")
        }
        if let thumbnail = await DataActor.shared.representativeThumbnail(forAlbumWithID: id, at: 0) {
            return .ok(imageData: thumbnail, contentType: "image/jpeg")
        }
        return .notFound()
    }

    private func handleGetPicThumbnail(id: String) async -> HTTPResponse {
        guard let data = await DataActor.shared.thumbnailData(forPicWithID: id) else {
            return .notFound()
        }
        return .ok(imageData: data, contentType: "image/jpeg")
    }

    private func handleGetPicImage(id: String) async -> HTTPResponse {
        guard let data = await DataActor.shared.imageData(forPicWithID: id) else {
            return .notFound()
        }
        let contentType = HTTPRequestParser.detectImageContentType(data)
        return .ok(imageData: data, contentType: contentType)
    }

    // MARK: - Video Routes

    private func handleGetPicVideo(id: String, rangeHeader: String?) async -> HTTPResponse {
        var fileURL = await DataActor.shared.videoURL(forPicWithID: id)
        if fileURL == nil {
            fileURL = await OriginalsManager.shared.materializedVideoURL(
                picID: id, in: DataActor.shared.collectionID
            )
        }
        guard let fileURL else { return .notFound() }
        let ext = fileURL.pathExtension
        let contentType = HTTPRequestParser.detectVideoContentType(forExtension: ext)
        return .videoResponse(fileURL: fileURL, contentType: contentType, rangeHeader: rangeHeader)
    }

    // MARK: - Upload Routes

    private func handleUploadToAlbum(id: String, request: HTTPRequest) async -> HTTPResponse {
        guard await DataActor.shared.album(for: id) != nil else {
            return .notFound()
        }
        return await processUpload(request: request, albumID: id)
    }

    private func handleUploadToRoot(request: HTTPRequest) async -> HTTPResponse {
        return await processUpload(request: request, albumID: nil)
    }

    private func processUpload(request: HTTPRequest, albumID: String?) async -> HTTPResponse {
        guard let contentType = request.headers["content-type"],
              contentType.contains("multipart/form-data"),
              let boundary = HTTPRequestParser.extractBoundary(from: contentType) else {
            return .badRequest("Expected multipart/form-data")
        }

        let files = HTTPRequestParser.parseMultipartFormData(body: request.body, boundary: boundary)
        guard !files.isEmpty else {
            return .badRequest("No files in upload")
        }

        var uploadedCount = 0
        for file in files {
            guard UIImage(data: file.data) != nil else { continue }
            let filename: String
            if file.filename.isEmpty {
                filename = Pic.newFilename()
            } else {
                let url = URL(fileURLWithPath: file.filename)
                filename = url.deletingPathExtension().lastPathComponent
            }
            await DataActor.shared.createPic(filename, data: file.data, inAlbumWithID: albumID)
            uploadedCount += 1
        }

        do {
            let json: [String: Any] = ["uploaded": uploadedCount]
            let data = try JSONSerialization.data(withJSONObject: json)
            return .ok(json: data)
        } catch {
            return .internalError(error.localizedDescription)
        }
    }

    // MARK: - HTML

    func serveMainPage() -> HTTPResponse {
        return .ok(html: Self.mainPageHTML)
    }

    // MARK: - JSON Helpers

    private static func albumToJSON(_ album: Album) -> [String: Any] {
        let hasCoverOrPics = album.hasCoverPhoto || album.picCount() > 0
        return [
            "id": album.id,
            "name": album.name,
            "hasCover": hasCoverOrPics,
            "albumCount": album.albumCount(),
            "picCount": album.picCount()
        ]
    }

    private static func picToJSON(_ pic: Pic) -> [String: Any] {
        var json: [String: Any] = [
            "id": pic.id,
            "name": pic.name,
            "dateAdded": ISO8601DateFormatter().string(from: pic.dateAdded),
            "isVideo": pic.isVideo
        ]
        if let duration = pic.duration {
            json["duration"] = duration
        }
        return json
    }
}
