import AppKit

@MainActor
final class AppLockController {

    private let auth: AuthenticationManager
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var promptsOnActivation = false

    static var isEnabled: Bool {
        UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")?.bool(forKey: "AppLockEnabled") ?? false
    }

    init(auth: AuthenticationManager) {
        self.auth = auth
    }

    func start() {
        if Self.isEnabled {
            auth.lock()
            auth.authenticate()
        } else {
            auth.isUnlocked = true
        }
        observe(NotificationCenter.default, NSApplication.didHideNotification) { $0.lock() }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { $0.authenticateIfLocked() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.lock() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.lock() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.lock() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.lock() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (AppLockController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func lock() {
        guard Self.isEnabled else { return }
        auth.lock()
        promptsOnActivation = true
    }

    private func authenticateIfLocked() {
        guard promptsOnActivation, Self.isEnabled, !auth.isUnlocked, !auth.isAuthenticating else { return }
        promptsOnActivation = false
        auth.authenticate()
    }
}
