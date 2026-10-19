import Foundation

public final class PicLibrary: Identifiable, Hashable, @unchecked Sendable {
    public static let defaultID = "__default__"

    public var id: String
    public var name: String
    public var syncEnabled: Bool

    public var isDefault: Bool { id == Self.defaultID }

    public init(id: String = PicLibrary.defaultID, name: String = "", syncEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.syncEnabled = syncEnabled
    }

    public static func == (lhs: PicLibrary, rhs: PicLibrary) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }

    public static func newID() -> String {
        let digits = String(format: "%08d", Int.random(in: 0...99_999_999))
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let alphanumeric = String((0..<4).map { _ in chars.randomElement()! })
        return "\(digits)-\(alphanumeric)"
    }
}
