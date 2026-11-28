import Engine
import SwiftUI

extension View {
    @MainActor func render(scale displayScale: CGFloat = 1.0) -> PlatformImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = displayScale
        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }

    @ViewBuilder
    func `if`<Modified: View>(_ condition: Bool, modifier: (Self) -> Modified) -> some View {
        if condition {
            modifier(self)
        } else {
            self
        }
    }
}
