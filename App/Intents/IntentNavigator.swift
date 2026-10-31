import Observation

@MainActor @Observable
final class IntentNavigator {

    static let shared = IntentNavigator()

    enum Destination: Equatable {
        case library(id: String)
        case album(id: String, libraryID: String)
        case pic(id: String, albumID: String?, libraryID: String)
    }

    var pendingDestination: Destination?

    func open(_ destination: Destination) {
        pendingDestination = destination
    }
}
