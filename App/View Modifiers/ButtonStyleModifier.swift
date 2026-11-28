import SwiftUI

struct ButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
#if os(macOS)
            .buttonStyle(.borderless)
            .tint(.primary)
#else
            .buttonStyle(.plain)
#endif
    }
}

extension View {
    func buttonStyleAdaptive() -> some View {
        modifier(ButtonStyleModifier())
    }
}
