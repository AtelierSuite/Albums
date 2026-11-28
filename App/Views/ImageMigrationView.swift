import Engine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ImageMigrationView: View {

    var manager: ImageMigrationManager

    @State private var displayedThumbnail: Data?

    private var progressTotal: Float { Float(max(manager.total, 1)) }

    var body: some View {
        VStack(spacing: 24.0) {
            Spacer()
            previewImage
                .overlay(
                    RoundedRectangle(cornerRadius: 20.0)
                        .strokeBorder(.separator, lineWidth: 1.0)
                )
            VStack(spacing: 8.0) {
                Text("Migration.Title", tableName: "More")
                    .font(.title2)
                    .fontWeight(.semibold)
                phaseLabel
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12.0) {
                if manager.total > 0 {
                    ProgressView(value: Float(manager.completed), total: progressTotal)
                        .progressViewStyle(.linear)
                        .tint(.accent)
                    Text("\(manager.completed)/\(manager.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.accent)
                }
            }
            Spacer()
            warningBox
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled()
        .task {
            while !Task.isCancelled {
                displayedThumbnail = manager.latestThumbnail
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private var warningBox: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
            Text("Migration.Warning", tableName: "More")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12.0)
        .glassEffect(.regular.tint(.orange.opacity(0.2)), in: RoundedRectangle(cornerRadius: 20.0))
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch manager.phase {
        case .preparing: Text("Migration.Phase.Preparing", tableName: "More")
        case .copying: Text("Migration.Phase.Copying", tableName: "More")
        case .verifying: Text("Migration.Phase.Verifying", tableName: "More")
        case .reclaiming: Text("Migration.Phase.Reclaiming", tableName: "More")
        }
    }

    private var previewImage: some View {
        RoundedRectangle(cornerRadius: 20.0)
            .fill(.quaternary)
            .overlay {
                if let displayedThumbnail, let image = PlatformImage(data: displayedThumbnail) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160.0, height: 160.0)
            .clipShape(RoundedRectangle(cornerRadius: 20.0))
    }
}
