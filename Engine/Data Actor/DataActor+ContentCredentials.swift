import Foundation
@preconcurrency import SQLite

public enum ContentCredentialsSource: Sendable {
    case imageData(Data)
    case videoFile(URL)
}

extension DataActor {

    public func picIDsNeedingContentCredentialsScan(version: Int, limit: Int) -> [String] {
        let query = picsTable
            .filter(picDateDeleted == nil && picContentCredentialsVersion < version)
            .select(picId)
            .order(picDateAdded.desc)
            .limit(limit)
        guard let rows = try? database.safeRows(query) else { return [] }
        return rows.compactMap { try? $0.get(picId) }
    }

    public func contentCredentialsSource(forPicWithID id: String) -> ContentCredentialsSource? {
        let query = picsTable.filter(picId == id).select(picMediaType)
        guard let row = try? database.pluck(query),
              let mediaType = try? row.get(picMediaType) else { return nil }
        if mediaType == MediaType.video.rawValue {
            return videoURL(forPicWithID: id).map { .videoFile($0) }
        }
        guard let data = imageData(forPicWithID: id), !data.isEmpty else { return nil }
        return .imageData(data)
    }

    public func contentCredentialsVersion(forPicWithID id: String) -> Int {
        let query = picsTable.filter(picId == id).select(picContentCredentialsVersion)
        return (try? database.pluck(query).flatMap { try? $0.get(picContentCredentialsVersion) }) ?? 0
    }

    public func setContentCredentials(_ credentials: ContentCredentials?, version: Int,
                                      forPicWithID id: String) {
        let json = credentials
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        _ = try? database.run(picsTable.filter(picId == id).update(
            picContentCredentials <- json,
            picContentCredentialsVersion <- version,
            picAIContent <- credentials?.aiContentKind?.rawValue
        ))
    }

    public func contentCredentials(forPicWithID id: String) -> ContentCredentialsScanResult {
        let query = picsTable
            .filter(picId == id)
            .select(picContentCredentials, picContentCredentialsVersion)
        guard let row = try? database.pluck(query),
              let version = try? row.get(picContentCredentialsVersion), version > 0 else {
            return .notScanned
        }
        guard let json = (try? row.get(picContentCredentials)) ?? nil,
              let credentials = try? JSONDecoder().decode(ContentCredentials.self, from: Data(json.utf8)) else {
            return .notFound
        }
        return .found(credentials)
    }
}
