import AppIntents

enum PicOrder: String, AppEnum {
    case newest
    case oldest
    case random

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("Entity.Order", table: "Intents"))
    }

    static var caseDisplayRepresentations: [PicOrder: DisplayRepresentation] {
        [
            .newest: DisplayRepresentation(title: LocalizedStringResource("Order.Newest", table: "Intents")),
            .oldest: DisplayRepresentation(title: LocalizedStringResource("Order.Oldest", table: "Intents")),
            .random: DisplayRepresentation(title: LocalizedStringResource("Order.Random", table: "Intents"))
        ]
    }
}
