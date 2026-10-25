import Foundation

public enum AIContentKind: Int, Codable, Sendable {
    case generated = 1
    case assisted = 2
}

public struct ContentCredentials: Codable, Sendable, Hashable {

    public enum SourceType: String, Codable, Sendable {
        case aiGenerated
        case aiAssisted
        case digitalCapture
        case digitalCreation

        public var aiContentKind: AIContentKind? {
            switch self {
            case .aiGenerated: .generated
            case .aiAssisted: .assisted
            case .digitalCapture, .digitalCreation: nil
            }
        }
    }

    public enum Validation: String, Codable, Sendable {
        case trusted
        case untrustedSigner
        case modified
        case invalid
    }

    public struct Ingredient: Codable, Sendable, Hashable {
        public var title: String?
        public var format: String?
        public var relationship: String?
        public var generator: String?
        public var sourceType: SourceType?
        public var hasCredentials: Bool

        public init(title: String?, format: String?, relationship: String?,
                    generator: String?, sourceType: SourceType?, hasCredentials: Bool) {
            self.title = title
            self.format = format
            self.relationship = relationship
            self.generator = generator
            self.sourceType = sourceType
            self.hasCredentials = hasCredentials
        }
    }

    public var sourceType: SourceType?
    public var generator: String?
    public var generatorVersion: String?
    public var signer: String?
    public var signedAt: Date?
    public var validation: Validation
    public var ingredients: [Ingredient]
    public var doNotTrain: Bool

    public var aiContentKind: AIContentKind? { sourceType?.aiContentKind }

    public init(sourceType: SourceType?, generator: String?, generatorVersion: String?,
                signer: String?, signedAt: Date?, validation: Validation,
                ingredients: [Ingredient], doNotTrain: Bool) {
        self.sourceType = sourceType
        self.generator = generator
        self.generatorVersion = generatorVersion
        self.signer = signer
        self.signedAt = signedAt
        self.validation = validation
        self.ingredients = ingredients
        self.doNotTrain = doNotTrain
    }
}

public enum ContentCredentialsScanResult: Sendable, Hashable {
    case notScanned
    case notFound
    case found(ContentCredentials)
}
