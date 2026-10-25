import C2PA
import Engine
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ContentCredentialsReader {

    static let version = 1

    private static let settingsJSON: String? = {
        func resource(_ name: String, _ ext: String) -> String? {
            Bundle.main.url(forResource: name, withExtension: ext)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        let definition = C2PASettingsDefinition(
            version: 1,
            trust: TrustSettings(
                trustAnchors: resource("C2PATrustAnchors", "pem"),
                trustConfig: resource("C2PATrustConfig", "cfg"),
                allowedList: resource("C2PAAllowedCertificates", "pem")
            ),
            core: CoreSettings(allowedNetworkHosts: []),
            verify: VerifySettings(
                verifyAfterReading: true,
                verifyTrust: true,
                verifyTimestampTrust: true,
                ocspFetch: false,
                remoteManifestFetch: false
            )
        )
        return try? definition.toJSON()
    }()

    private static let supportedMIMETypes = Set(Reader.supportedMimeTypes)

    static func read(_ source: ContentCredentialsSource) -> ContentCredentials? {
        guard let json = manifestJSON(for: source) else { return nil }
        return parse(json)
    }

    private static func manifestJSON(for source: ContentCredentialsSource) -> String? {
        do {
            let context = try settingsJSON
                .map { try C2PAContext(settings: C2PASettings(json: $0)) } ?? C2PAContext()
            let reader: Reader
            switch source {
            case .imageData(let data):
                guard let format = mimeType(ofImageData: data) else { return nil }
                reader = try Reader(context: context, format: format, stream: Stream(data: data))
            case .videoFile(let url):
                guard let format = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
                      supportedMIMETypes.contains(format) else { return nil }
                reader = try Reader(context: context, format: format, stream: Stream(readFrom: url))
            }
            return try reader.json()
        } catch {
            return nil
        }
    }

    private static func mimeType(ofImageData data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let format = UTType(typeIdentifier)?.preferredMIMEType,
              supportedMIMETypes.contains(format) else { return nil }
        return format
    }

    // MARK: - Parsing

    typealias JSONObject = [String: Any]

    static func parse(_ json: String) -> ContentCredentials? {
        guard let store = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? JSONObject,
              let manifests = store["manifests"] as? [String: JSONObject],
              let activeLabel = store["active_manifest"] as? String,
              let active = manifests[activeLabel] else { return nil }
        let generator = generatorInfo(of: active)
        let signature = active["signature_info"] as? JSONObject
        return ContentCredentials(
            sourceType: sourceType(of: active, in: manifests, depth: 0),
            generator: generator.name,
            generatorVersion: generator.version,
            signer: (signature?["issuer"] as? String) ?? (signature?["common_name"] as? String),
            signedAt: (signature?["time"] as? String).flatMap(parseDate),
            validation: validation(of: store),
            ingredients: ingredients(of: active, in: manifests),
            doNotTrain: doesOptOutOfTraining(active)
        )
    }

    private static func generatorInfo(of manifest: JSONObject) -> (name: String?, version: String?) {
        if let info = (manifest["claim_generator_info"] as? [JSONObject])?.first,
           let name = info["name"] as? String {
            return (name, info["version"] as? String)
        }
        guard let claimGenerator = manifest["claim_generator"] as? String,
              let product = claimGenerator.split(separator: " ").first else { return (nil, nil) }
        let parts = product.split(separator: "/", maxSplits: 1).map(String.init)
        return (parts.first?.replacingOccurrences(of: "_", with: " "), parts.count > 1 ? parts[1] : nil)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private static func validation(of store: JSONObject) -> ContentCredentials.Validation {
        let state = store["validation_state"] as? String
        if state == "Trusted" { return .trusted }
        var failureCodes = Set(((store["validation_status"] as? [JSONObject]) ?? [])
            .compactMap { $0["code"] as? String })
        let activeResults = (store["validation_results"] as? JSONObject)?["activeManifest"] as? JSONObject
        failureCodes.formUnion(((activeResults?["failure"] as? [JSONObject]) ?? [])
            .compactMap { $0["code"] as? String })
        let trustCodes: Set<String> = ["signingCredential.untrusted", "timeStamp.untrusted"]
        let otherFailures = failureCodes.subtracting(trustCodes)
        if otherFailures.contains(where: { $0.hasSuffix(".mismatch") }) { return .modified }
        if !otherFailures.isEmpty || (state == "Invalid" && failureCodes.isEmpty) { return .invalid }
        return .untrustedSigner
    }

    private static func ingredients(of manifest: JSONObject,
                                    in manifests: [String: JSONObject]) -> [ContentCredentials.Ingredient] {
        ((manifest["ingredients"] as? [JSONObject]) ?? []).map { ingredient in
            let ingredientManifest = (ingredient["active_manifest"] as? String).flatMap { manifests[$0] }
            return ContentCredentials.Ingredient(
                title: (ingredient["title"] as? String) ?? (ingredientManifest?["title"] as? String),
                format: ingredient["format"] as? String,
                relationship: ingredient["relationship"] as? String,
                generator: ingredientManifest.flatMap { generatorInfo(of: $0).name },
                sourceType: ingredientManifest.flatMap { sourceType(of: $0, in: manifests, depth: 1) },
                hasCredentials: ingredientManifest != nil
            )
        }
    }

    private static func actions(of manifest: JSONObject) -> [JSONObject] {
        ((manifest["assertions"] as? [JSONObject]) ?? [])
            .filter { ($0["label"] as? String)?.hasPrefix("c2pa.actions") == true }
            .flatMap { (($0["data"] as? JSONObject)?["actions"] as? [JSONObject]) ?? [] }
    }

    private static func ownSourceType(of manifest: JSONObject) -> ContentCredentials.SourceType? {
        var result: ContentCredentials.SourceType?
        for action in actions(of: manifest) {
            guard let uri = action["digitalSourceType"] as? String,
                  let term = uri.split(separator: "/").last else { continue }
            let candidate: ContentCredentials.SourceType? = switch term {
            case "trainedAlgorithmicMedia":
                action["action"] as? String == "c2pa.created" ? .aiGenerated : .aiAssisted
            case "compositeWithTrainedAlgorithmicMedia": .aiAssisted
            case "digitalCapture": .digitalCapture
            case "digitalCreation", "digitalArt": .digitalCreation
            default: nil
            }
            result = moreSignificant(result, candidate)
        }
        return result
    }

    private static func sourceType(of manifest: JSONObject, in manifests: [String: JSONObject],
                                   depth: Int) -> ContentCredentials.SourceType? {
        var result = ownSourceType(of: manifest)
        guard depth < 8 else { return result }
        for ingredient in (manifest["ingredients"] as? [JSONObject]) ?? [] {
            guard let label = ingredient["active_manifest"] as? String,
                  let ingredientManifest = manifests[label],
                  let inherited = sourceType(of: ingredientManifest, in: manifests, depth: depth + 1)
            else { continue }
            let isParent = ingredient["relationship"] as? String == "parentOf"
            if inherited.aiContentKind != nil {
                result = moreSignificant(result, isParent ? inherited : .aiAssisted)
            } else if isParent, result == nil {
                result = inherited
            }
        }
        return result
    }

    private static func moreSignificant(_ lhs: ContentCredentials.SourceType?,
                                        _ rhs: ContentCredentials.SourceType?) -> ContentCredentials.SourceType? {
        func rank(_ type: ContentCredentials.SourceType?) -> Int {
            switch type {
            case .aiGenerated: 4
            case .aiAssisted: 3
            case .digitalCapture: 2
            case .digitalCreation: 1
            case nil: 0
            }
        }
        return rank(rhs) > rank(lhs) ? rhs : lhs
    }

    private static func doesOptOutOfTraining(_ manifest: JSONObject) -> Bool {
        ((manifest["assertions"] as? [JSONObject]) ?? [])
            .filter { ($0["label"] as? String)?.contains("training-mining") == true }
            .compactMap { ($0["data"] as? JSONObject)?["entries"] as? [String: JSONObject] }
            .contains { entries in
                entries.contains { key, value in
                    key.contains("training") && value["use"] as? String == "notAllowed"
                }
            }
    }
}
