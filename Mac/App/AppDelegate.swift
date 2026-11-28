import AppKit
import Engine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let model = AppModel()
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func showMainWindow(_ sender: Any? = nil) {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(model: model)
        }
        mainWindowController?.showWindow(nil)
    }

    @objc func zoomIn(_ sender: Any?) {
        NotificationCenter.default.post(name: .viewerZoomCommand, object: ViewerZoomCommand.zoomIn)
    }

    @objc func zoomOut(_ sender: Any?) {
        NotificationCenter.default.post(name: .viewerZoomCommand, object: ViewerZoomCommand.zoomOut)
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        NotificationCenter.default.post(name: .viewerZoomCommand, object: ViewerZoomCommand.actualSize)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: model)
            settingsWindowController?.window?.center()
        }
        settingsWindowController?.showWindow(nil)
    }
}
