import Engine
import SwiftUI
import UIKit

struct LabsTestDataView: View {

    @EnvironmentObject var navigation: NavigationManager

    @State private var picCount: Int = 12000
    @State private var albumCount: Int = 40
    @State private var legacyBlobs: Bool = false

    @State private var isGenerating: Bool = false
    @State private var generatedCount: Int = 0
    @State private var totalCount: Int = 0

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Labs.TestData.Pics", table: "More")) {
                    TextField("", value: $picCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(String(localized: "Labs.TestData.Albums", table: "More")) {
                    TextField("", value: $albumCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle(String(localized: "Labs.TestData.LegacyBlobs", table: "More"), isOn: $legacyBlobs)
            } header: {
                Text("Labs.TestData.Options", tableName: "More")
            } footer: {
                Text("Labs.TestData.LegacyBlobs.Description", tableName: "More")
            }
            Section {
                Button {
                    generate()
                } label: {
                    Text("Labs.TestData.Generate", tableName: "More")
                }
                .disabled(picCount <= 0)
            } footer: {
                Text("Labs.TestData.Warning", tableName: "More")
            }
        }
        .navigationTitle(String(localized: "Labs.TestData", table: "More"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isGenerating) {
            StatusView(type: .inProgress,
                       title: .custom("Labs.TestData.Generating", tableName: "More"),
                       currentCount: generatedCount,
                       totalCount: totalCount)
                .phonePresentationDetents([.medium])
                .interactiveDismissDisabled()
        }
    }

    private func generate() {
        generatedCount = 0
        totalCount = picCount
        isGenerating = true
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            await SampleDataGenerator.generate(
                picCount: max(0, picCount), albumCount: max(0, albumCount),
                into: DataActor.shared, legacyBlobs: legacyBlobs
            ) { completed, total in
                generatedCount = completed
                totalCount = total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            isGenerating = false
            navigation.signalDataDeleted()
        }
    }
}
