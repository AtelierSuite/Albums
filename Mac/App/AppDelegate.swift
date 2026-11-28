import AppKit
import Engine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {

    let model = AppModel()
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private lazy var appLock = AppLockController(auth: model.auth)
    private let backgroundSync = BackgroundSyncScheduler()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build()
        appLock.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        backgroundSync.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await SyncManager.shared.refresh() }
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

    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindow()
        model.openRequests.urls.append(contentsOf: urls)
    }

    @objc func showMainWindow(_ sender: Any? = nil) {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(model: model)
        }
        mainWindowController?.showWindow(nil)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: model)
            settingsWindowController?.window?.center()
        }
        settingsWindowController?.showWindow(nil)
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

    @objc func previousPic(_ sender: Any?) {
        NotificationCenter.default.post(name: .viewerNavigateCommand, object: ViewerNavigateCommand.previous)
    }

    @objc func nextPic(_ sender: Any?) {
        NotificationCenter.default.post(name: .viewerNavigateCommand, object: ViewerNavigateCommand.next)
    }

    @objc func newAlbum(_ sender: Any?) {
        MacMenuState.shared.album?.createAlbum()
    }

    @objc func importFiles(_ sender: Any?) {
        MacMenuState.shared.album?.importFiles()
    }

    @objc func importPhotos(_ sender: Any?) {
        MacMenuState.shared.album?.importPhotos()
    }

    @objc func importVideos(_ sender: Any?) {
        MacMenuState.shared.album?.importVideos()
    }

    @objc func browseAlbums(_ sender: Any?) {
        MacMenuState.shared.album?.browseAlbums()
    }

    @objc func selectFolder(_ sender: Any?) {
        MacMenuState.shared.album?.selectFolder()
    }

    @objc func toggleSectionHeaders(_ sender: Any?) {
        guard let binding = MacMenuState.shared.album?.options.hideSectionHeaders else { return }
        binding.wrappedValue.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isAlbumWindowKey = NSApp.keyWindow === mainWindowController?.window
        let isUnlocked = !AppLockController.isEnabled || model.auth.isUnlocked
        switch menuItem.action {
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(zoomToActualSize(_:)),
             #selector(previousPic(_:)), #selector(nextPic(_:)):
            return isUnlocked && NSApp.keyWindow?.windowController is ViewerWindowController
        case #selector(toggleSectionHeaders(_:)):
            menuItem.state = MacMenuState.shared.album?.options.hideSectionHeaders.wrappedValue == true ? .on : .off
            return isUnlocked && isAlbumWindowKey && MacMenuState.shared.album != nil
        case #selector(newAlbum(_:)), #selector(importFiles(_:)), #selector(importPhotos(_:)),
             #selector(importVideos(_:)), #selector(browseAlbums(_:)), #selector(selectFolder(_:)):
            return isUnlocked && isAlbumWindowKey && MacMenuState.shared.album != nil
        default:
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let showsAlbumOptions = MacMenuState.shared.album != nil
        for item in menu.items where item.tag == MainMenuBuilder.albumOptionsTag {
            item.isHidden = !showsAlbumOptions
        }
    }
}
