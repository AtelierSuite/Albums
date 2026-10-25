import Engine
import SwiftUI

extension AIContentKind {
    var systemImage: String { "sparkles" }

    var label: LocalizedStringResource {
        switch self {
        case .generated: LocalizedStringResource("AI.Generated", table: "ContentCredentials")
        case .assisted: LocalizedStringResource("AI.Assisted", table: "ContentCredentials")
        }
    }
}

struct AIContentBadge: View {

    var kind: AIContentKind
    var isCompact: Bool = false

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: isCompact ? 7.0 : 10.0, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: isCompact ? 14.0 : 22.0, height: isCompact ? 14.0 : 22.0)
            .background(.black.opacity(0.6), in: .circle)
            .padding(isCompact ? 2.0 : 4.0)
            .accessibilityElement()
            .accessibilityLabel(Text(kind.label))
    }
}

struct AIContentChip: View {

    var kind: AIContentKind

    var body: some View {
        Label {
            Text(kind.label)
        } icon: {
            Image(systemName: kind.systemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .background(.bar, in: .capsule)
        .contentShape(.capsule)
    }
}
