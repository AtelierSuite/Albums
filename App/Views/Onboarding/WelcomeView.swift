import SwiftUI

struct WelcomeView: View {

    var onContinue: () -> Void

    private let appName = "Albums"

    private var welcomeTitle: Text {
        let format = String(localized: "Onboarding.Welcome.Title")
        let accent = Text(appName).foregroundStyle(.accent)
        let parts = format.components(separatedBy: "%@")
        guard parts.count == 2 else { return accent }
        return Text(parts[0]) + accent + Text(parts[1])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16.0) {
                welcomeTitle
                    .fontWeight(.black)
                    .font(.largeTitle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24.0)
                Spacer()
                VStack(alignment: .leading, spacing: 32.0) {
                    FeatureRow(
                        symbol: "rectangle.stack.fill",
                        gradient: LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        title: "Onboarding.Feature.NestedAlbums.Title",
                        blurb: "Onboarding.Feature.NestedAlbums.Blurb"
                    )
                    FeatureRow(
                        symbol: "sparkle.magnifyingglass",
                        primary: .orange, secondary: .yellow,
                        title: "Onboarding.Feature.Duplicates.Title",
                        blurb: "Onboarding.Feature.Duplicates.Blurb"
                    )
                    FeatureRow(
                        symbol: "wand.and.stars",
                        primary: .purple, secondary: .pink,
                        title: "Onboarding.Feature.Sorting.Title",
                        blurb: "Onboarding.Feature.Sorting.Blurb"
                    )
                    FeatureRow(
                        symbol: "square.stack.3d.up.fill",
                        primary: .green, secondary: .teal,
                        title: "Onboarding.Feature.Libraries.Title",
                        blurb: "Onboarding.Feature.Libraries.Blurb"
                    )
                }
                Spacer()
            }
            .padding(18.0)
        }
        .background {
            LinearGradient(
                colors: [.accent.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0.0) {
            VStack(spacing: 12.0) {
                Button {
                    onContinue()
                } label: {
                    Text("Onboarding.Continue")
                        .fontWeight(.bold)
                }
                .tint(.accent)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .buttonSizing(.flexible)
            }
            .padding()
        }
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
    }
}

private struct FeatureRow: View {

    var symbol: String
    var primary: Color = .accent
    var secondary: Color = .accent
    var gradient: LinearGradient?
    var title: LocalizedStringKey
    var blurb: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            icon
                .font(.system(size: 40.0))
                .frame(width: 56.0, height: 56.0)
            VStack(alignment: .leading, spacing: 6.0) {
                Text(title)
                    .fontWeight(.bold)
                Text(blurb)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0.0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let gradient {
            Image(systemName: symbol)
                .foregroundStyle(gradient)
        } else {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(primary, secondary)
        }
    }
}

extension WelcomeView {
    static func shouldShow(currentVersion: String, lastSeenVersion: String) -> Bool {
        guard let current = majorMinor(currentVersion) else { return false }
        guard let last = majorMinor(lastSeenVersion) else { return true }
        if current.major != last.major { return current.major > last.major }
        return current.minor > last.minor
    }

    static func majorMinor(_ version: String) -> (major: Int, minor: Int)? {
        let components = version.split(separator: ".")
        guard let major = components.first.flatMap({ Int($0) }) else { return nil }
        let minor = components.count > 1 ? (Int(components[1]) ?? 0) : 0
        return (major, minor)
    }
}
