import Engine
import Foundation
import SwiftUI

struct SettingsBackupView: View {

    enum Phase: Equatable {
        case preparing
        case confirming
        case exporting
        case completed
        case failed
    }

    @Environment(\.dismiss) var dismiss
    var destinationURL: URL
    var collectionID: String
    var libraryName: String

    @State private var phase: Phase = .preparing
    @State private var estimatedBytes: Int64 = 0
    @State private var availableBytes: Int64 = 0
    @State private var progressCurrent: Int = 0
    @State private var progressTotal: Int = 0
    @State private var failureTitle: StatusView.StatusTitle =
        .custom("Backup.Error.Destination", tableName: "More")
    @State private var freeSpaceKnown: Bool = true
    @State private var format: BackupFormat = .archive
    @State private var unavailablePicIDs: [String] = []
    @State private var isSkipApproved: Bool = false

    private var hasEnoughSpace: Bool {
        !freeSpaceKnown
            || availableBytes >= DataActor.requiredFreeSpace(forBackupPayload: estimatedBytes)
    }

    private var canStart: Bool {
        hasEnoughSpace && (unavailablePicIDs.isEmpty || isSkipApproved)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .preparing:
                    StatusView(type: .inProgress,
                               title: .custom("Backup.Preparing", tableName: "More"))
                case .confirming:
                    confirmation
                case .exporting:
                    StatusView(type: .inProgress, title: .backupExporting,
                               currentCount: progressCurrent, totalCount: progressTotal)
                case .completed:
                    completion(title: .backupExportCompleted, isError: false, message: nil)
                case .failed:
                    completion(title: failureTitle, isError: true, message: nil)
                }
            }
            .padding(20.0)
            .navigationTitle("ViewTitle.Backup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .phonePresentationDetents([.medium])
        .interactiveDismissDisabled(phase == .exporting || phase == .preparing)
        .task { await prepare() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var confirmation: some View {
        VStack(alignment: .center, spacing: 16.0) {
            Spacer()
            Text("Backup.Confirm.Title", tableName: "More")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Backup.Confirm.Message", tableName: "More")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 6.0) {
                Picker("Backup.Format", selection: $format) {
                    ForEach(BackupFormat.allCases) { option in
                        Text(option.title, tableName: "More").tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(format.description, tableName: "More")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 6.0) {
                summaryRow("Backup.Confirm.Size", value: byteString(estimatedBytes))
                if freeSpaceKnown {
                    summaryRow("Backup.Confirm.Available", value: byteString(availableBytes))
                }
            }
            .font(.callout)
            if freeSpaceKnown && !hasEnoughSpace {
                Text("Backup.Error.InsufficientSpace", tableName: "More")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if !unavailablePicIDs.isEmpty {
                unavailableConsent
            }
            Spacer()
            Button {
                Task { await runBackup() }
            } label: {
                Text("Backup.Start", tableName: "More")
                    .bold()
            }
            .tint(.accent)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
            .disabled(!canStart)
            Button { dismiss() } label: {
                Text("Shared.Cancel")
            }
            .tint(.secondary)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
        }
    }

    private var unavailableConsent: some View {
        VStack(alignment: .center, spacing: 8.0) {
            Text("Backup.Unavailable.Message.\(unavailablePicIDs.count)", tableName: "More")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Toggle(isOn: $isSkipApproved) {
                Text("Backup.Unavailable.Skip", tableName: "More")
                    .font(.callout)
            }
        }
    }

    private func summaryRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label, tableName: "More").foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    @ViewBuilder
    private func completion(title: StatusView.StatusTitle, isError: Bool,
                            message: StatusView.StatusTitle?) -> some View {
        VStack(alignment: .center, spacing: 16.0) {
            StatusView(type: isError ? .error : .success, title: title, message: message)
            Button { dismiss() } label: {
                Text("Shared.OK").bold()
            }
            .tint(.accent)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func prepare() async {
        guard phase == .preparing else { return }
        let dataActor = DataActor.instance(for: collectionID)
        let cid = collectionID
        let estimate = await dataActor.backupEstimate(sizeProvider: { picID in
            await OriginalsManager.shared.originalSize(picID: picID, in: cid)
        }, availability: { picID in
            await OriginalsManager.shared.hasCloudOriginal(picID: picID, in: cid)
        })
        let accessed = destinationURL.startAccessingSecurityScopedResource()
        let values = try? destinationURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
        ])
        if accessed { destinationURL.stopAccessingSecurityScopedResource() }
        estimatedBytes = estimate.bytes
        unavailablePicIDs = estimate.unavailablePicIDs
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            availableBytes = important
            freeSpaceKnown = true
        } else if let plain = values?.volumeAvailableCapacity {
            availableBytes = Int64(plain)
            freeSpaceKnown = true
        } else {
            freeSpaceKnown = false
        }
        withAnimation(.smooth.speed(2.0)) { phase = .confirming }
    }

    private func runBackup() async {
        phase = .exporting
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let dataActor = DataActor.instance(for: collectionID)
        let cid = collectionID
        let originalProvider: @Sendable (String) async -> Data? = { picID in
            await OriginalsManager.shared.fetchOriginal(picID: picID, in: cid,
                                                        timeoutSeconds: 60, retries: 3)
        }
        let prefetch: @Sendable ([String]) async -> Void = { picIDs in
            await OriginalsManager.shared.prefetchOriginals(picIDs: picIDs, in: cid)
        }
        let sizeProvider: @Sendable (String) async -> Int64? = { picID in
            await OriginalsManager.shared.originalSize(picID: picID, in: cid)
        }
        let skipped = Set(unavailablePicIDs)
        let onProgress: @MainActor (Int, Int) -> Void = { current, total in
            progressCurrent = current
            progressTotal = total
        }
        do {
            switch format {
            case .archive:
                try await dataActor.backupDatabase(
                    to: destinationURL, libraryName: libraryName,
                    originalProvider: originalProvider, sizeProvider: sizeProvider,
                    prefetch: prefetch, skipping: skipped, progress: onProgress
                )
            case .folders:
                try await dataActor.exportFolderArchive(
                    to: destinationURL, libraryName: libraryName,
                    originalProvider: originalProvider, sizeProvider: sizeProvider,
                    prefetch: prefetch, skipping: skipped, progress: onProgress
                )
            }
            withAnimation(.smooth.speed(2.0)) { phase = .completed }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as BackupError {
            failureTitle = title(for: error)
            withAnimation(.smooth.speed(2.0)) { phase = .failed }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            failureTitle = .custom(LocalizedStringKey(error.localizedDescription))
            withAnimation(.smooth.speed(2.0)) { phase = .failed }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func title(for error: BackupError) -> StatusView.StatusTitle {
        switch error {
        case .insufficientSpace:
            .custom("Backup.Error.InsufficientSpace", tableName: "More")
        case .originalUnavailable:
            .custom("Backup.Error.Incomplete", tableName: "More")
        case .destinationInaccessible, .sourceUnreadable, .nothingRestored:
            .custom("Backup.Error.Destination", tableName: "More")
        }
    }
}
