import SwiftUI

struct SettingsExperimentsView: View {

    @AppStorage(wrappedValue: false, "DebugCloudEverywhere") var showCloudStatusEverywhere: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16.0) {
                    HStack(alignment: .center, spacing: 16.0) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.0, height: 24.0)
                            .foregroundStyle(.white)
                        Text("Debug.Warning.Title", tableName: "More")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.white)
                    }
                    Text("Debug.Warning.Text", tableName: "More")
                        .foregroundStyle(.white)
                }
                .padding(20.0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.red)
            }
            Section {
                Toggle("Experiments.ShowCloudStatusEverywhere", isOn: $showCloudStatusEverywhere)
            }
        }
        .navigationTitle("ViewTitle.Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}
