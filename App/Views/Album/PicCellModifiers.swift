import SwiftUI

struct DeferredOverlayModifier<Layer: View>: ViewModifier {

    @ViewBuilder var layer: () -> Layer

    @State private var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    layer()
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isActive = true
            }
    }
}

struct PicTransitionSourceModifier: ViewModifier {

    @Environment(ViewerManager.self) private var viewer

    let picID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if viewer.displayedPicID == picID {
            content
                .matchedTransitionSource(id: picID, in: namespace)
        } else {
            content
        }
    }
}
