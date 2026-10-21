import SwiftUI

public struct SelectionOverlay: View {
    let isSelected: Bool

    public init(_ isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if isSelected {
                Color.black.opacity(0.3)
                    .clipShape(.rect(cornerRadius: 4.0))
            }
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            .padding(6)
        }
    }
}
