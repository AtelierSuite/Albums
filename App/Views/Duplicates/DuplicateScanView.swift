import SwiftUI
import UIKit

struct DuplicateScanView: View {

    @Environment(\.dismiss) var dismiss

    var scanScope: DuplicateScanManager.ScanScope
    var collectionID: String?

    @State var scanManager: DuplicateScanManager

    init(scanScope: DuplicateScanManager.ScanScope, collectionID: String? = nil) {
        self.scanScope = scanScope
        self.collectionID = collectionID
        self._scanManager = State(initialValue: DuplicateScanManager(collectionID: collectionID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if scanManager.isScanning {
                    scanProgressContent
                } else if scanManager.scanPhase == .done {
                    DuplicateResultsView(scanManager: scanManager)
                } else {
                    scanConfigContent
                }
            }
            .navigationTitle("ViewTitle.DuplicateChecker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !scanManager.isScanning {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !scanManager.isScanning && scanManager.scanPhase == .idle {
                        Button {
                            Task {
                                await scanManager.scan(scope: scanScope)
                            }
                        } label: {
                            Label(
                                String(localized: "Duplicates.StartScan", table: "Photos"),
                                systemImage: "arrow.right"
                            )
                        }
                        .accessibilityIdentifier("startDuplicateScan")
                    }
                }
            }
        }
        .phonePresentationDetents([.medium, .large])
        .interactiveDismissDisabled(scanManager.isScanning)
        .onChange(of: scanManager.isScanning) { _, isScanning in
            UIApplication.shared.isIdleTimerDisabled = isScanning
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
#if DEBUG
        .task {
            if ScreenshotSeeder.isActive && ScreenshotSeeder.findsDuplicates {
                await scanManager.scan(scope: scanScope)
            }
        }
#endif
    }

    private var scanConfigContent: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8.0) {
                    Text("Duplicates.Sensitivity", tableName: "Photos")
                    Slider(value: $scanManager.hammingThreshold, in: 1...15)
                        .tint(.accent)
                    HStack {
                        Text("Duplicates.Sensitivity.Strict", tableName: "Photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Duplicates.Sensitivity.Loose", tableName: "Photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Duplicates.Settings", tableName: "Photos")
            }
        }
    }

    private var scanProgressContent: some View {
        VStack {
            if scanManager.scanPhase == .computingHashes {
                StatusView(type: .inProgress,
                           title: .duplicatesScanningComputingHashes,
                           currentCount: scanManager.scanProgress,
                           totalCount: scanManager.scanTotal)
            } else {
                StatusView(type: .inProgress,
                           title: .duplicatesScanningComparing)
            }
        }
    }
}
