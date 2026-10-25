import SwiftUI

struct DuplicateKeepBadge: View {

    var body: some View {
        Label {
            Text("Duplicates.Keep", tableName: "Photos")
        } icon: {
            Image(systemName: "checkmark.shield.fill")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7.0)
        .padding(.vertical, 3.0)
        .glassEffect(.regular.tint(.green), in: .capsule)
        .padding(6.0)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct DuplicateFavoriteBadge: View {

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 10.0, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 22.0, height: 22.0)
            .glassEffect(.regular.tint(.pink), in: .circle)
            .padding(4.0)
            .accessibilityLabel(Text("Duplicates.Favorite", tableName: "Photos"))
    }
}
