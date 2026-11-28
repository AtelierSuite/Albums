#if canImport(UIKit)
import UIKit
#endif

public enum Haptics {

    public enum Notification {
        case success
        case warning
        case error
    }

    @MainActor
    public static func notify(_ notification: Notification) {
        #if os(iOS)
        let type: UINotificationFeedbackGenerator.FeedbackType = switch notification {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }

    @MainActor
    public static func selectionChanged() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
