import SwiftUI

public struct SaveErrorView: View {

    var session: SaveSession
    var title: String
    var message: String
    var systemImage: String

    public init(session: SaveSession, title: String, message: String, systemImage: String) {
        self.session = session
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button(role: .close) {
                session.cancel()
            } label: {
                Text("Shared.Close", tableName: "Saving", bundle: .engine)
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(20.0)
        }
        .background(Color(uiColor: .systemBackground))
    }
}
