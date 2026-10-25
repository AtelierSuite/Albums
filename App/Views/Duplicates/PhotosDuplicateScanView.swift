import Photos
import SwiftUI

struct PhotosDuplicateScanView: View {

    @Environment(\.dismiss) var dismiss

    @AppStorage("DuplicatesAutoSelectCriterion") var autoSelectCriterion: DuplicateAutoSelectCriterion = .none
    @AppStorage("DuplicatesAutoSelectPrefersProtected") var autoSelectPrefersProtected: Bool = true

    @State var scanManager = PhotosDuplicateScanManager()

    let collection: PHAssetCollection

    var body: some View {
        NavigationStack {
            Group {
                if scanManager.isScanning {
                    scanProgressContent
                } else if scanManager.scanPhase == .done {
                    PhotosDuplicateResultsView(scanManager: scanManager)
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
                                await scanManager.scan(in: collection, autoSelect: autoSelectOptions)
                            }
                        } label: {
                            Label(
                                String(localized: "Duplicates.StartScan", table: "Photos"),
                                systemImage: "arrow.right"
                            )
                        }
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
            Section {
                Picker(selection: $autoSelectCriterion) {
                    ForEach(DuplicateAutoSelectCriterion.allCases) { criterion in
                        Text(criterion.titleKey)
                            .tag(criterion)
                    }
                } label: {
                    Text("Duplicates.AutoSelect.Rule", tableName: "Photos")
                }
                .accessibilityIdentifier("duplicateAutoSelectRule")
                if autoSelectCriterion != .none {
                    Toggle(isOn: $autoSelectPrefersProtected) {
                        Text("Duplicates.AutoSelect.PreferFavorites", tableName: "Photos")
                    }
                }
            } header: {
                Text("Duplicates.AutoSelect", tableName: "Photos")
            } footer: {
                if autoSelectCriterion != .none {
                    Text("Duplicates.AutoSelect.Footer", tableName: "Photos")
                }
            }
        }
    }

    private var autoSelectOptions: DuplicateAutoSelectOptions {
        DuplicateAutoSelectOptions(criterion: autoSelectCriterion, prefersProtected: autoSelectPrefersProtected)
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
