#if DEBUG
import SwiftUI

struct LabsSettingsPane: View {

    @State private var isFileExplorerPresented: Bool = false
    @State private var isTestDataPresented: Bool = false

    var body: some View {
        SettingsForm {
            LabeledContent(String(localized: "Labs", table: "More")) {
                VStack(alignment: .leading, spacing: 8.0) {
                    Button(String(localized: "Labs.FileExplorer", table: "More")) {
                        isFileExplorerPresented = true
                    }
                    Button(String(localized: "Labs.TestData", table: "More")) {
                        isTestDataPresented = true
                    }
                    SettingsNote(text: String(localized: "Labs.Description", table: "More"))
                }
            }
        }
        .sheet(isPresented: $isFileExplorerPresented) {
            labsSheet { LabsFileExplorerView() }
        }
        .sheet(isPresented: $isTestDataPresented) {
            labsSheet { LabsTestDataView() }
        }
    }

    private func labsSheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) {
                            isFileExplorerPresented = false
                            isTestDataPresented = false
                        }
                    }
                }
        }
        .frame(minWidth: 520.0, minHeight: 440.0)
    }
}
#endif
