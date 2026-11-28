import AppKit
import SwiftUI

struct AppLockCover: ViewModifier {

    @Environment(AuthenticationManager.self) private var auth

    @AppStorage("AppLockEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var isAppLockEnabled: Bool = false

    func body(content: Content) -> some View {
        let isLocked = isAppLockEnabled && !auth.isUnlocked
        content
            .overlay {
                if isLocked {
                    LockScreenView()
                        .transition(.opacity)
                }
            }
            .background {
                WindowToolbarHider(isHidden: isLocked)
            }
            .animation(.easeInOut(duration: 0.3), value: isLocked)
    }
}

private struct WindowToolbarHider: NSViewRepresentable {

    let isHidden: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let isHidden = isHidden
        DispatchQueue.main.async {
            guard let toolbar = nsView.window?.toolbar, toolbar.isVisible == isHidden else { return }
            toolbar.isVisible = !isHidden
        }
    }
}

extension View {
    func appLockCover() -> some View {
        modifier(AppLockCover())
    }
}
