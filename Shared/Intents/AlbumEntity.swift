import AppIntents

struct AlbumEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("Entity.Album", table: "Intents"))
    }

    let id: String
    let libraryID: String
    let name: String
    var libraryName: String?

    var displayRepresentation: DisplayRepresentation {
        if let libraryName {
            DisplayRepresentation(title: "\(name)", subtitle: "\(libraryName)")
        } else {
            DisplayRepresentation(title: "\(name)")
        }
    }
}
