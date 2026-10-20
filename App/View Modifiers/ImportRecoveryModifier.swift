import SwiftUI

struct ImportRecoveryModifier: ViewModifier {

    @Environment(ImportManager.self) var importManager
    @EnvironmentObject var navigation: NavigationManager

    @State private var isRecoveryAlertPresented: Bool = false

    private var needsRecovery: Bool {
        !importManager.interruptedJobs.isEmpty && !importManager.isRunning
    }

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Import.Interrupted.Title", tableName: "Import"),
                isPresented: $isRecoveryAlertPresented
            ) {
                Button {
                    Task {
                        await importManager.resumeInterruptedJobs()
                    }
                } label: {
                    Text("Import.Interrupted.Resume", tableName: "Import")
                }
                Button {
                    discardInterruptedJobs(deletingImported: false)
                } label: {
                    Text("Import.Cancel.KeepImported", tableName: "Import")
                }
                Button(role: .destructive) {
                    discardInterruptedJobs(deletingImported: true)
                } label: {
                    Text("Import.Cancel.DeleteImported", tableName: "Import")
                }
                Button(role: .cancel) {
                } label: {
                    Text("Import.Interrupted.Later", tableName: "Import")
                }
            } message: {
                Text("Import.Interrupted.Message.\(importManager.interruptedRemainingCount)", tableName: "Import")
            }
            .sheet(isPresented: .constant(importManager.isRunning && importManager.isResumedRun)) {
                ImportProgressView()
            }
            .onChange(of: needsRecovery, initial: true) { _, needsRecovery in
                isRecoveryAlertPresented = needsRecovery
            }
            .onChange(of: importManager.lastFinishedJobID) {
                navigation.signalDataChanged()
            }
    }

    private func discardInterruptedJobs(deletingImported: Bool) {
        Task {
            await importManager.discardInterruptedJobs(deletingImported: deletingImported)
        }
    }
}
