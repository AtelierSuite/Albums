import AppKit

extension MainMenuBuilder {

    static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.File"))
        menu.addItem(item("Menu.NewAlbum", action: #selector(AppDelegate.newAlbum(_:)), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(item("Menu.ImportFiles", action: #selector(AppDelegate.importFiles(_:)), keyEquivalent: "i",
                          modifiers: [.command, .shift]))
        let importItem = NSMenuItem(title: String(localized: "Shared.Import"), action: nil, keyEquivalent: "")
        let importMenu = NSMenu(title: importItem.title)
        importMenu.addItem(localizedItem("Import.SelectPhotos", table: "Import",
                                         action: #selector(AppDelegate.importPhotos(_:))))
        importMenu.addItem(localizedItem("Import.SelectVideos", table: "Import",
                                         action: #selector(AppDelegate.importVideos(_:))))
        importMenu.addItem(localizedItem("Import.BrowseAlbums", table: "Import",
                                         action: #selector(AppDelegate.browseAlbums(_:))))
        importMenu.addItem(localizedItem("Import.SelectFolder", table: "Import",
                                         action: #selector(AppDelegate.selectFolder(_:))))
        importItem.submenu = importMenu
        menu.addItem(importItem)
        menu.addItem(.separator())
        menu.addItem(item("Menu.Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }

    static func localizedItem(_ key: String, table: String? = nil, action: Selector?,
                              keyEquivalent: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let title = String(localized: String.LocalizationValue(key), table: table)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
