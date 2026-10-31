import Foundation

// MARK: - HTTP Models

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
    var queryParameters: [String: String]
}

struct HTTPResponse: Sendable {
    var statusCode: Int
    var statusText: String
    var headers: [String: String]
    var body: Data

    static func ok(json: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            ],
            body: json
        )
    }

    static func ok(html: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusText: "OK",
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(html.utf8)
        )
    }

    static func ok(imageData: Data, contentType: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Content-Type": contentType,
                "Cache-Control": "public, max-age=3600"
            ],
            body: imageData
        )
    }

    static func videoResponse(
        fileURL: URL,
        contentType: String,
        rangeHeader: String?
    ) -> HTTPResponse {
        guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int,
              let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return .notFound()
        }
        defer { try? fileHandle.close() }

        if let rangeHeader, rangeHeader.hasPrefix("bytes=") {
            let rangeSpec = String(rangeHeader.dropFirst("bytes=".count))
            let parts = rangeSpec.split(separator: "-", maxSplits: 1)
            let start = Int(parts[0]) ?? 0
            let end: Int
            if parts.count > 1 && !parts[1].isEmpty {
                end = min(Int(parts[1]) ?? (fileSize - 1), fileSize - 1)
            } else {
                // Serve up to 1 MB per range request
                end = min(start + 1_048_575, fileSize - 1)
            }

            guard start <= end && start < fileSize else {
                return HTTPResponse(
                    statusCode: 416,
                    statusText: "Range Not Satisfiable",
                    headers: ["Content-Range": "bytes */\(fileSize)"],
                    body: Data()
                )
            }

            try? fileHandle.seek(toOffset: UInt64(start))
            let length = end - start + 1
            let data = fileHandle.readData(ofLength: length)

            return HTTPResponse(
                statusCode: 206,
                statusText: "Partial Content",
                headers: [
                    "Content-Type": contentType,
                    "Content-Range": "bytes \(start)-\(end)/\(fileSize)",
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "public, max-age=3600"
                ],
                body: data
            )
        } else {
            let data = fileHandle.readDataToEndOfFile()
            return HTTPResponse(
                statusCode: 200,
                statusText: "OK",
                headers: [
                    "Content-Type": contentType,
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "public, max-age=3600"
                ],
                body: data
            )
        }
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(
            statusCode: 404,
            statusText: "Not Found",
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"Not Found\"}".utf8)
        )
    }

    static func badRequest(_ message: String) -> HTTPResponse {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        return HTTPResponse(
            statusCode: 400,
            statusText: "Bad Request",
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"\(escaped)\"}".utf8)
        )
    }

    static func internalError(_ message: String) -> HTTPResponse {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        return HTTPResponse(
            statusCode: 500,
            statusText: "Internal Server Error",
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"\(escaped)\"}".utf8)
        )
    }

    func serialized() -> Data {
        var headerString = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (key, value) in headers {
            headerString += "\(key): \(value)\r\n"
        }
        headerString += "Content-Length: \(body.count)\r\n"
        headerString += "Connection: close\r\n"
        headerString += "\r\n"
        var data = Data(headerString.utf8)
        data.append(body)
        return data
    }
}

// MARK: - Multipart

struct MultipartFile: Sendable {
    var filename: String
    var contentType: String
    var data: Data
}

// MARK: - HTTP Request Parser (nonisolated)

enum HTTPRequestParser {

    static func parse(headerString: String, body: Data) -> HTTPRequest {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: body, queryParameters: [:])
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"

        var path = rawPath
        var queryParameters: [String: String] = [:]
        if let questionIndex = rawPath.firstIndex(of: "?") {
            path = String(rawPath[rawPath.startIndex..<questionIndex])
            let queryString = String(rawPath[rawPath.index(after: questionIndex)...])
            for pair in queryString.split(separator: "&") {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                    let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                    queryParameters[key] = value
                }
            }
        }

        path = path.removingPercentEncoding ?? path

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body,
            queryParameters: queryParameters
        )
    }

    static func extractBoundary(from contentType: String) -> String? {
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary=") {
                var boundary = String(trimmed.dropFirst("boundary=".count))
                if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                    boundary = String(boundary.dropFirst().dropLast())
                }
                return boundary
            }
        }
        return nil
    }

    static func parseMultipartFormData(body: Data, boundary: String) -> [MultipartFile] {
        let boundaryData = Data("--\(boundary)".utf8)
        let crlfCrlf = Data("\r\n\r\n".utf8)
        let crlf = Data("\r\n".utf8)

        var files: [MultipartFile] = []
        var searchStart = body.startIndex

        var parts: [Range<Data.Index>] = []
        while let range = body.range(of: boundaryData, in: searchStart..<body.endIndex) {
            parts.append(range)
            searchStart = range.upperBound
        }

        for idx in 0..<parts.count {
            let partStart = parts[idx].upperBound
            let partEnd: Data.Index
            if idx + 1 < parts.count {
                partEnd = parts[idx + 1].lowerBound
            } else {
                partEnd = body.endIndex
            }

            guard partStart < partEnd else { continue }
            let partData = body[partStart..<partEnd]

            // Skip the \r\n after boundary marker
            guard partData.count > 2 else { continue }
            let contentData: Data
            if partData.starts(with: crlf) {
                contentData = Data(partData[partData.index(partData.startIndex, offsetBy: 2)...])
            } else {
                contentData = Data(partData)
            }

            // Check for closing boundary marker (--)
            if contentData.starts(with: Data("--".utf8)) { continue }

            guard let headerBodySplit = contentData.range(of: crlfCrlf) else { continue }
            let headersData = contentData[contentData.startIndex..<headerBodySplit.lowerBound]
            var fileBody = Data(contentData[headerBodySplit.upperBound...])

            // Remove trailing \r\n if present
            if fileBody.count >= 2 && fileBody.suffix(2) == crlf {
                fileBody = Data(fileBody.dropLast(2))
            }

            guard let headersString = String(data: headersData, encoding: .utf8) else { continue }

            var filename = ""
            var partContentType = "application/octet-stream"

            for line in headersString.components(separatedBy: "\r\n") {
                let lower = line.lowercased()
                if lower.hasPrefix("content-disposition:") {
                    if let fnRange = line.range(of: "filename=\"") {
                        let afterQuote = line[fnRange.upperBound...]
                        if let endQuote = afterQuote.firstIndex(of: "\"") {
                            filename = String(afterQuote[afterQuote.startIndex..<endQuote])
                        }
                    }
                } else if lower.hasPrefix("content-type:") {
                    partContentType = line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
                }
            }

            if !fileBody.isEmpty {
                files.append(MultipartFile(filename: filename, contentType: partContentType, data: fileBody))
            }
        }

        return files
    }

    static func detectImageContentType(_ data: Data) -> String {
        guard data.count >= 4 else { return "application/octet-stream" }
        let bytes = [UInt8](data.prefix(4))

        // JPEG
        if bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return "image/jpeg"
        }
        // PNG
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        // GIF
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        }
        // WebP (RIFF....WEBP)
        if data.count >= 12 {
            let riffBytes = [UInt8](data.prefix(12))
            if riffBytes[0] == 0x52 && riffBytes[1] == 0x49 && riffBytes[2] == 0x46 && riffBytes[3] == 0x46
                && riffBytes[8] == 0x57 && riffBytes[9] == 0x45 && riffBytes[10] == 0x42 && riffBytes[11] == 0x50 {
                return "image/webp"
            }
        }
        // HEIC
        if data.count >= 12 {
            if let ftypString = String(data: data[4..<12], encoding: .ascii) {
                if ftypString.hasPrefix("ftyp") {
                    let brand = String(ftypString.dropFirst(4))
                    if brand.hasPrefix("heic") || brand.hasPrefix("mif1") || brand.hasPrefix("heis") {
                        return "image/heic"
                    }
                }
            }
        }

        return "image/jpeg"
    }

    static func detectVideoContentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        default:
            return "video/mp4"
        }
    }
}
