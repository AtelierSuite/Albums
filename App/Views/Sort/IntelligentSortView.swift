import Engine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IntelligentSortView: View {

    @Environment(\.dismiss) var dismiss

    var scope: IntelligentSortManager.SortScope
    var collectionID: String?

    @State var sortManager: IntelligentSortManager

    init(scope: IntelligentSortManager.SortScope, collectionID: String? = nil) {
        self.scope = scope
        self.collectionID = collectionID
        self._sortManager = State(initialValue: IntelligentSortManager(collectionID: collectionID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortManager.isRunning {
                    runProgressContent
                } else if sortManager.phase == .done {
                    IntelligentSortResultsView(sortManager: sortManager)
                } else {
                    configContent
                }
            }
            .navigationTitle(Text("Sort.Title", tableName: "Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .sheetLeading) {
                    if !sortManager.isRunning {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .sheetTrailing) {
                    if !sortManager.isRunning && sortManager.phase == .idle {
                        Button {
                            Task {
                                await sortManager.sort(scope: scope)
                            }
                        } label: {
                            Label(
                                String(localized: "Sort.Start", table: "Photos"),
                                systemImage: "arrow.right"
                            )
                        }
                    }
                }
            }
        }
        .phonePresentationDetents([.medium, .large])
        .interactiveDismissDisabled(sortManager.isRunning)
        .onChange(of: sortManager.isRunning) { _, isRunning in
            UIApplication.shared.isIdleTimerDisabled = isRunning
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var configContent: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8.0) {
                    Text("Sort.Strictness", tableName: "Photos")
                    Slider(value: $sortManager.looseness, in: 0...1)
                        .tint(.accent)
                    HStack {
                        Text("Sort.Strictness.Strict", tableName: "Photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Sort.Strictness.Loose", tableName: "Photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sort.Settings", tableName: "Photos")
            } footer: {
                Text("Sort.Explanation", tableName: "Photos")
            }
        }
    }

    private var runProgressContent: some View {
        VStack {
            switch sortManager.phase {
            case .analyzingPics:
                StatusView(type: .inProgress,
                           title: .intelligentSortAnalyzing,
                           currentCount: sortManager.progress,
                           totalCount: sortManager.total)
            case .matching:
                StatusView(type: .inProgress,
                           title: .intelligentSortMatching,
                           currentCount: sortManager.progress,
                           totalCount: sortManager.total)
            default:
                if sortManager.total > 0 {
                    StatusView(type: .inProgress,
                               title: .intelligentSortBuildingModels,
                               currentCount: sortManager.progress,
                               totalCount: sortManager.total)
                } else {
                    StatusView(type: .inProgress,
                               title: .intelligentSortBuildingModels)
                }
            }
        }
    }
}
