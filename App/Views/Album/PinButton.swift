import SwiftUI

struct PinButton: View {

    var isPinned: Bool
    var action: () -> Void

    var body: some View {
        if isPinned {
            Button("Shared.Unpin", systemImage: "pin.slash", action: action)
        } else {
            Button("Shared.Pin", systemImage: "pin", action: action)
        }
    }
}
