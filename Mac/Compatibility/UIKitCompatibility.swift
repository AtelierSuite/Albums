import AppKit
import Engine

enum UIUserInterfaceIdiom {
    case unspecified
    case phone
    case pad
    case mac
}

@MainActor
final class UIDevice {
    static let current = UIDevice()
    let userInterfaceIdiom: UIUserInterfaceIdiom = .mac
}

@MainActor
final class UIApplication {

    enum State {
        case active
        case inactive
        case background
    }

    static let shared = UIApplication()
    static let openSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"

    private var idleActivity: NSObjectProtocol?

    var isIdleTimerDisabled: Bool = false {
        didSet {
            guard isIdleTimerDisabled != oldValue else { return }
            if isIdleTimerDisabled {
                idleActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated], reason: "Albums is working"
                )
            } else if let idleActivity {
                ProcessInfo.processInfo.endActivity(idleActivity)
                self.idleActivity = nil
            }
        }
    }

    var applicationState: State {
        NSApp.isActive ? .active : .background
    }

    let supportsAlternateIcons = false
    let alternateIconName: String? = nil

    func setAlternateIconName(_ alternateIconName: String?) async throws {}

    func open(_ url: URL, options: [AnyHashable: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        let opened = NSWorkspace.shared.open(url)
        completionHandler?(opened)
    }
}

@MainActor
final class UIPasteboard {
    static let general = UIPasteboard()

    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.setString(newValue, forType: .string)
            }
        }
    }

    var image: PlatformImage? {
        get { NSImage(pasteboard: NSPasteboard.general) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.writeObjects([newValue])
            }
        }
    }
}

extension NSImage {
    func byPreparingForDisplay() async -> NSImage? {
        self
    }

    func byPreparingThumbnail(ofSize size: CGSize) async -> NSImage? {
        preparingThumbnail(of: size)
    }
}
