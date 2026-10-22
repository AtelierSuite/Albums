import SwiftUI

struct WebServerView: View {

    @Environment(WebServerManager.self) var webServer

    var body: some View {
        @Bindable var webServer = webServer
        Section {
            Toggle(
                String(localized: "WebServer", table: "WebServer"),
                isOn: Binding(
                    get: { webServer.isRunning },
                    set: { newValue in
                        if newValue {
                            webServer.start()
                        } else {
                            webServer.stop()
                        }
                    }
                )
            )
            if webServer.isRunning, let ipAddress = webServer.localIPAddress {
                LabeledContent(String(localized: "WebServer.Address", table: "WebServer")) {
                    Text(verbatim: "http://\(ipAddress):\(webServer.port)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.accent)
                        .textSelection(.enabled)
                }
                Toggle(
                    String(localized: "WebServer.KeepScreenOn", table: "WebServer"),
                    isOn: $webServer.keepScreenOn
                )
            }
        } header: {
            Text("WebServer.Header", tableName: "WebServer")
        } footer: {
            Text("WebServer.Description", tableName: "WebServer")
        }
    }
}
