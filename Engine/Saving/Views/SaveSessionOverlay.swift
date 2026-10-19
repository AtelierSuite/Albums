import SwiftUI

public struct SaveSessionOverlay: View {

    var session: SaveSession

    public init(session: SaveSession) {
        self.session = session
    }

    public var body: some View {
        switch session.phase {
        case .idle:
            EmptyView()
        case .checking, .saving:
            status {
                ProgressView()
                    .controlSize(.large)
                Text(session.destinationTitle.map {
                    String(localized: "Saving.SavingTo.\($0)", table: "Saving", bundle: .engine)
                } ?? String(localized: "Saving.Saving", table: "Saving", bundle: .engine))
                .font(.headline)
            }
        case .saved:
            status {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64.0))
                    .symbolRenderingMode(.multicolor)
                    .transition(.scale.combined(with: .opacity))
                Text(session.destinationTitle.map {
                    String(localized: "Saving.SavedTo.\($0)", table: "Saving", bundle: .engine)
                } ?? String(localized: "Saving.Saved", table: "Saving", bundle: .engine))
                .font(.headline)
            }
        case .failed(let message):
            status {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64.0))
                    .symbolRenderingMode(.multicolor)
                Text("Saving.Failed", tableName: "Saving", bundle: .engine)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(role: .close) {
                    session.cancel()
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        case .duplicates(let matches):
            DuplicateWarningView(session: session, matches: matches)
        }
    }

    private func status<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16.0) {
            content()
        }
        .padding(32.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
