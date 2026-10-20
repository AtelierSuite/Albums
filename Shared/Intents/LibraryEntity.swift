import AppIntents

struct LibraryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("Entity.Library", table: "Intents"))
    }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func displayName(for name: String) -> String {
        name.isEmpty ? String(localized: "Library.Default", table: "Intents") : name
    }
}
