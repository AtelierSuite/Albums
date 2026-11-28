import AppKit

extension MainMenuBuilder {

    static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.View"))
        menu.addItem(item(
            "Menu.ShowSidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .control]
        ))
        menu.addItem(.separator())
        menu.addItem(item("Menu.ActualSize", action: #selector(AppDelegate.zoomToActualSize(_:)), keyEquivalent: "0"))
        menu.addItem(item("Menu.ZoomIn", action: #selector(AppDelegate.zoomIn(_:)), keyEquivalent: "+"))
        menu.addItem(item("Menu.ZoomOut", action: #selector(AppDelegate.zoomOut(_:)), keyEquivalent: "-"))
        menu.addItem(.separator())
        menu.addItem(item(
            "Menu.EnterFullScreen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
            modifiers: [.command, .control]
        ))
        return menu
    }
}
