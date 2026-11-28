import SwiftUI

struct WebServerSettingsPane: View {

    @Environment(WebServerManager.self) private var webServer

    var body: some View {
        @Bindable var webServer = webServer
        SettingsForm {
            LabeledContent(String(localized: "WebServer.Header", table: "WebServer")) {
                VStack(alignment: .leading, spacing: 6.0) {
                    Toggle(MacText.string("Settings.WebServer.Enable"), isOn: Binding(
                        get: { webServer.isRunning },
                        set: { isOn in
                            if isOn {
                                webServer.start()
                            } else {
                                webServer.stop()
                            }
                        }
                    ))
                    Toggle(String(localized: "WebServer.KeepScreenOn", table: "WebServer"),
                           isOn: $webServer.keepScreenOn)
                        .disabled(!webServer.isRunning)
                    SettingsNote(text: String(localized: "WebServer.Description", table: "WebServer"))
                }
            }
            if webServer.isRunning, let ipAddress = webServer.localIPAddress {
                LabeledContent(String(localized: "WebServer.Address", table: "WebServer")) {
                    Text(verbatim: "http://\(ipAddress):\(webServer.port)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
