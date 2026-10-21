import SwiftUI

struct ImportProgressView: View {

    var body: some View {
        NavigationStack {
            VStack(alignment: .center, spacing: 0.0) {
                ImportStatusView()
                ImportCancelButton()
            }
            .navigationTitle("ViewTitle.Import")
            .navigationBarTitleDisplayMode(.inline)
        }
        .phonePresentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

struct ImportStatusView: View {

    @Environment(ImportManager.self) var importManager

    var body: some View {
        StatusView(type: .inProgress, title: .importImporting,
                   currentCount: importManager.completedCount, totalCount: importManager.totalCount)
    }
}
