import SwiftUI

struct GeneralSettingsPane: View {

    @Environment(AuthenticationManager.self) private var auth

    @AppStorage("AppLockEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var isAppLockEnabled: Bool = false
    @AppStorage(viewerFitToScreenKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var fitToScreen: Bool = false
    @AppStorage(viewerBackgroundTypeKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var viewerBackgroundType: ViewerBackgroundType = .immersive
    @AppStorage(viewerShowResolutionKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var showResolutionByDefault: Bool = true
    @AppStorage(importShowNotificationKey, store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var showImportNotification: Bool = true

    var body: some View {
        SettingsForm {
            LabeledContent(String(localized: "Security", table: "More")) {
                VStack(alignment: .leading, spacing: 6.0) {
                    Toggle(String(localized: "AppLock", table: "More"), isOn: $isAppLockEnabled)
                        .disabled(auth.biometryType == .none)
                    SettingsNote(text: String(localized: "AppLock.Description", table: "More"))
                }
            }
            LabeledContent(String(localized: "Viewer", table: "More")) {
                VStack(alignment: .leading, spacing: 6.0) {
                    Toggle(String(localized: "Viewer.FitToScreen", table: "More"), isOn: $fitToScreen)
                    Toggle(String(localized: "Viewer.ShowResolution", table: "More"),
                           isOn: $showResolutionByDefault)
                }
            }
            LabeledContent(String(localized: "Viewer.BackgroundType", table: "More")) {
                Picker(String(localized: "Viewer.BackgroundType", table: "More"),
                       selection: $viewerBackgroundType) {
                    Text("Viewer.BackgroundType.Immersive", tableName: "More")
                        .tag(ViewerBackgroundType.immersive)
                    Text("Viewer.BackgroundType.FollowSystem", tableName: "More")
                        .tag(ViewerBackgroundType.followSystem)
                    Text("Viewer.BackgroundType.Dark", tableName: "More")
                        .tag(ViewerBackgroundType.dark)
                }
                .labelsHidden()
                .fixedSize()
            }
            LabeledContent(String(localized: "Import", table: "More")) {
                VStack(alignment: .leading, spacing: 6.0) {
                    Toggle(String(localized: "Import.ShowNotification", table: "More"),
                           isOn: $showImportNotification)
                    SettingsNote(text: String(localized: "Import.ShowNotification.Description", table: "More"))
                }
            }
        }
    }
}
