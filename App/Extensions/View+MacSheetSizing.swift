import SwiftUI

extension View {
    @ViewBuilder
    func macSheetSizing() -> some View {
        #if os(macOS)
        modifier(ResizableSheetSizing())
        #else
        self
        #endif
    }
}

