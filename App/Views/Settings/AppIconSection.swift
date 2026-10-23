import SwiftUI
import UIKit

struct AppIconSection: View {

    @State var selectedIcon: AppIcon = .vivid

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(AppIcon.allCases) { icon in
                        Button {
                            select(icon)
                        } label: {
                            AppIconTile(icon: icon, isSelected: icon == selectedIcon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.localizedName)
                        .accessibilityAddTraits(icon == selectedIcon ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("AppIcon", tableName: "More")
        }
        .onAppear {
            selectedIcon = AppIcon(alternateIconName: UIApplication.shared.alternateIconName)
        }
    }

    func select(_ icon: AppIcon) {
        guard icon != selectedIcon else { return }
        let previousIcon = selectedIcon
        selectedIcon = icon
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
            } catch {
                debugPrint(error.localizedDescription)
                selectedIcon = previousIcon
            }
        }
    }
}

struct AppIconTile: View {

    let icon: AppIcon
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(icon.previewImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.accent, lineWidth: 3)
                        .opacity(isSelected ? 1 : 0)
                }
            Text(icon.localizedName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 84)
        .contentShape(.rect)
    }
}
