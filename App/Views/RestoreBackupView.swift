import Engine
import SwiftUI

struct RestoreBackupView: View {

    var backupURL: URL
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigation: NavigationManager

    @State var isImporting: Bool = false
    @State var isCompleted: Bool = false
    @State var isError: Bool = false
    @State var rootAlbums: [Album] = []
    @State var importedCount: Int = 0
    @State var errorMessage: StatusView.StatusTitle?

    @State var fileSize: String?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                if isImporting {
                    StatusView(type: .inProgress, title: .backupRestoring)
                } else if isCompleted {
                    StatusView(type: .success, title: .backupRestoreCompleted(count: importedCount))
                } else if isError {
                    StatusView(type: .error, title: .backupRestoreError, message: errorMessage)
                } else {
                    VStack(alignment: .leading, spacing: 20.0) {
                        HStack(alignment: .top) {
                            Text("Shared.FileName")
                            Spacer()
                            Text(backupURL.lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let fileSize {
                            HStack {
                                Text("Shared.FileSize")
                                Spacer()
                                Text(fileSize)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20.0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isCompleted || isError {
                    Button {
                        dismiss()
                    } label: {
                        Text("Shared.OK")
                            .bold()
                            .padding(4.0)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.accent)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .padding(20.0)
                } else if !isImporting {
                    VStack(alignment: .leading, spacing: 8.0) {
                        Button {
                            startImport(targetAlbumID: nil)
                        } label: {
                            Text("Backup.Restore.Merge", tableName: "More")
                                .bold()
                                .padding(4.0)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.accent)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)

                        Text("Backup.Restore.Merge.Description", tableName: "More")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8.0)

                        Menu {
                            ForEach(rootAlbums) { rootAlbum in
                                AlbumHierarchyMenuItem(
                                    targetAlbum: rootAlbum, excludingAlbumID: ""
                                ) { destinationAlbum in
                                    startImport(targetAlbumID: destinationAlbum.id)
                                }
                            }
                        } label: {
                            Text("Backup.Restore.ToAlbum", tableName: "More")
                                .bold()
                                .padding(4.0)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.accent)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)

                        Text("Backup.Restore.ToAlbum.Description", tableName: "More")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20.0)
                }
            }
            .navigationTitle("ViewTitle.RestoreBackup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isImporting && !isCompleted && !isError {
                        Button(role: .cancel) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .phonePresentationDetents([.medium])
        .interactiveDismissDisabled()
        .task {
            rootAlbums = (try? await DataActor.shared.albumsWithCounts(in: nil, sortedBy: .nameAscending)) ?? []
            if let resources = try? backupURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                fileSize = formatter.string(fromByteCount: Int64(size))
            }
        }
    }

    static func message(for error: Error) -> StatusView.StatusTitle {
        switch error {
        case BackupError.sourceUnreadable:
            .custom("Backup.Restore.Error.Unreadable", tableName: "More")
        case BackupError.nothingRestored:
            .custom("Backup.Restore.Error.Empty", tableName: "More")
        default:
            .custom(LocalizedStringKey(error.localizedDescription))
        }
    }

    func startImport(targetAlbumID: String?) {
        withAnimation(.smooth.speed(2.0)) {
            isImporting = true
            UIApplication.shared.isIdleTimerDisabled = true
        } completion: {
            Task {
                do {
                    let imported = try await DataActor.shared.importFromBackup(
                        at: backupURL, targetAlbumID: targetAlbumID
                    )
                    await MainActor.run {
                        importedCount = imported
                        isImporting = false
                        isCompleted = true
                        navigation.dataVersion += 1
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                } catch {
                    let message = Self.message(for: error)
                    await MainActor.run {
                        errorMessage = message
                        isImporting = false
                        isError = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
            }
        }
    }
}
