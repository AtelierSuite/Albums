import SwiftUI

struct SettingsForm<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18.0) {
            content()
        }
        .labeledContentStyle(SettingsColumnStyle())
        .toggleStyle(.checkbox)
        .padding(.horizontal, 32.0)
        .padding(.vertical, 28.0)
        .frame(width: 600.0, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsColumnStyle: LabeledContentStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10.0) {
            configuration.label
                .multilineTextAlignment(.trailing)
                .frame(width: 160.0, alignment: .trailing)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsNote: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360.0, alignment: .leading)
    }
}
