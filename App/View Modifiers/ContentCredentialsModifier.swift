import Engine
import SwiftUI

struct ContentCredentialsModifier: ViewModifier {

    @Environment(\.scenePhase) var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                await ContentCredentialsScanner.shared.scheduleScan(after: .seconds(3))
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    Task { await ContentCredentialsScanner.shared.scheduleScan(after: .seconds(3)) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataActorDidMutateLocally)) { note in
                if let collectionID = note.object as? String {
                    Task { await ContentCredentialsScanner.shared.scheduleScan(libraryIDs: [collectionID]) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDidApplyRemoteChanges)) { _ in
                Task { await ContentCredentialsScanner.shared.scheduleScan() }
            }
    }
}
