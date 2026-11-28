import Foundation

@MainActor
enum MacGestureTracker {

    enum Kind {
        case zoomPinch
        case gridPinch
    }

    private static var active: Set<Kind> = []

    static func begin(_ kind: Kind) -> Bool {
        active.insert(kind).inserted
    }

    static func end(_ kind: Kind) {
        active.remove(kind)
    }
}
