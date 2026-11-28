import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {

    init(model: AppModel) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        tabs.transitionOptions = [.allowUserInteraction]
        var panes = [
            SettingsTab(MacText.string("Settings.General"), "gearshape") { GeneralSettingsPane() },
            SettingsTab(String(localized: "WebServer.Header", table: "WebServer"), "network") {
                WebServerSettingsPane()
            }
        ]
        #if DEBUG
        panes.append(SettingsTab(String(localized: "Labs", table: "More"), "flask") { LabsSettingsPane() })
        #endif
        panes.append(SettingsTab(String(localized: "Attributions", table: "More"), "doc.text") {
            AttributionsSettingsPane()
        })
        for pane in panes {
            let hostingController = NSHostingController(rootView: AnyView(pane.content.appLockCover().environment(model)))
            hostingController.sizingOptions = .intrinsicContentSize
            hostingController.title = pane.title
            let item = NSTabViewItem(viewController: hostingController)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        if let first = tabs.tabViewItems.first?.viewController {
            tabs.resize(window, toFit: first, animated: false)
        }
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct SettingsTab {
    let title: String
    let symbolName: String
    let content: AnyView

    init<Content: View>(_ title: String, _ symbolName: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbolName = symbolName
        self.content = AnyView(content())
    }
}
