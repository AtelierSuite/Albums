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
                SaveErrorView(session: session,
                              title: String(localized: "LastUsed.Empty.Title", table: "Saving", bundle: .engine),
                              message: String(localized: "LastUsed.Empty.Message", table: "Saving", bundle: .engine),
                              systemImage: "clock.arrow.circlepath")
            }
            SaveSessionOverlay(session: session)
        }
        .background(Color(uiColor: .systemBackground))
    }
}
