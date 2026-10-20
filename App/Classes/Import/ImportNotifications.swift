import Foundation
import UserNotifications

@MainActor
enum ImportNotifications {

    private static var isEnabled: Bool {
        UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")?
            .object(forKey: importShowNotificationKey) as? Bool ?? true
    }

    static func sendCompleted(count: Int, albumName: String?) async {
        let body: String
        if count == 0 {
            body = String(localized: "Import.Notification.Empty", table: "Import")
        } else if let albumName {
            body = String(localized: "Import.Notification.Body.\(count).\(albumName)", table: "Import")
        } else {
            body = String(localized: "Import.Completed.Text.\(count)", table: "Import")
        }
        await send(body: body)
    }

    static func sendInterrupted() async {
        await send(body: String(localized: "Import.Notification.Interrupted", table: "Import"))
    }

    private static func send(body: String) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        let freshStatus = await center.notificationSettings().authorizationStatus
        guard freshStatus == .authorized || freshStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "ViewTitle.Import")
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
