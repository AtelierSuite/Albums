import SwiftUI

struct ImportCancelButton: View {

    @Environment(ImportManager.self) var importManager

    @State private var isConfirmingCancel: Bool = false

    var body: some View {
        Group {
            if importManager.isStopping {
                HStack(spacing: 8.0) {
                    ProgressView()
                    Text("Import.Cancelling", tableName: "Import")
                        .foregroundStyle(.secondary)
                }
                .padding(4.0)
                .frame(maxWidth: .infinity)
            } else {
                Button(role: .destructive) {
                    importManager.pause()
                    isConfirmingCancel = true
                } label: {
                    Text("Import.Cancel", tableName: "Import")
                        .bold()
                        .padding(4.0)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(!importManager.isRunning)
            }
        }
        .padding(20.0)
        .confirmationDialog(
            Text("Import.Cancel.Title", tableName: "Import"),
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                importManager.cancel(deletingImported: true)
            } label: {
                Text("Import.Cancel.DeleteImported", tableName: "Import")
            }
            Button {
                importManager.cancel(deletingImported: false)
            } label: {
                Text("Import.Cancel.KeepImported", tableName: "Import")
            }
            Button(role: .cancel) {
            } label: {
                Text("Import.Cancel.Back", tableName: "Import")
            }
        } message: {
            Text("Import.Cancel.Message", tableName: "Import")
        }
        .onChange(of: isConfirmingCancel) { _, isConfirming in
            if !isConfirming && !importManager.isStopping {
                importManager.resume()
            }
        }
    }
}
