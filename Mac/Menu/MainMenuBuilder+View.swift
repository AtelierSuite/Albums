import AppKit
import SwiftUI

extension MainMenuBuilder {

    static let albumOptionsTag = 1001

    static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: MacText.string("Menu.View"))
        menu.delegate = NSApp.delegate as? NSMenuDelegate
        menu.addItem(item(
            "Menu.ShowSidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .control]
        ))
        menu.addItem(.separator())
        for item in albumOptionItems() {
            item.tag = albumOptionsTag
            menu.addItem(item)
        }
        menu.addItem(localizedItem("Command.PreviousPic", action: #selector(AppDelegate.previousPic(_:)),
                                   keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))))
        menu.addItem(localizedItem("Command.NextPic", action: #selector(AppDelegate.nextPic(_:)),
                                   keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))))
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

    private static func albumOptionItems() -> [NSMenuItem] {
        let albums = NSMenuItem(title: String(localized: "Albums.Albums", table: "Albums"),
                                action: nil, keyEquivalent: "")
        albums.submenu = NSHostingMenu(rootView: AlbumOptionsMenuContent(kind: .albums))
        let pics = NSMenuItem(title: String(localized: "Albums.Pics", table: "Albums"),
                              action: nil, keyEquivalent: "")
        pics.submenu = NSHostingMenu(rootView: AlbumOptionsMenuContent(kind: .pics))
        let hideHeaders = localizedItem("Albums.HideHeaders", table: "Albums",
                                        action: #selector(AppDelegate.toggleSectionHeaders(_:)))
        return [albums, pics, hideHeaders, .separator()]
    }
}
