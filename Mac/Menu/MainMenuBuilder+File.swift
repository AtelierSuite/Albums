import AppKit

extension MainMenuBuilder {

    static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.File"))
        menu.addItem(item("Menu.Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }
}
