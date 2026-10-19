import SwiftUI

public struct LastUsedSaveView: View {

    var session: SaveSession
    private let destination = LastUsedDestination.current

    public init(session: SaveSession) {
        self.session = session
    }

    public var body: some View {
        ZStack {
            if let destination {
                if session.items.isEmpty {
                    NothingToSaveView(session: session)
                } else {
                    VStack(spacing: 20.0) {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 48.0))
                            .foregroundStyle(.tint)
                        VStack(spacing: 4.0) {
                            Text(destination.title)
                                .font(.title3)
                                .bold()
                            Text(destination.appName)
                                .foregroundStyle(.secondary)
                        }
                        SharedItemsStrip(items: session.items)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await session.save(to: destination)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "LastUsed.Empty.Title", table: "Saving", bundle: .engine),
                          systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("LastUsed.Empty.Message", tableName: "Saving", bundle: .engine)
                } actions: {
                    Button(role: .close) { session.cancel() }
                        .buttonStyle(.glass)
                }
            }
            SaveSessionOverlay(session: session)
        }
        .background(Color(uiColor: .systemBackground))
    }
}
