import SwiftUI

struct AttributionsSettingsPane: View {

    private static let sourceCodeURL = URL(string: "https://github.com/Atelier/Albums")!

    @Environment(\.openURL) private var openURL
    @State private var selection: Dependency.ID?

    private var selectedDependency: Dependency? {
        Dependency.all.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16.0) {
            HStack(alignment: .top, spacing: 16.0) {
                List(Dependency.all, selection: $selection) { dependency in
                    Text(dependency.name)
                        .tag(dependency.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.fill.quinary, in: .rect(cornerRadius: 10.0))
                .frame(width: 200.0)
                ScrollView {
                    Text(selectedDependency?.licenseText ?? "")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16.0)
                }
                .background(.fill.quinary, in: .rect(cornerRadius: 10.0))
            }
            Button {
                openURL(Self.sourceCodeURL)
            } label: {
                Label(String(localized: "GitHub", table: "More"),
                      systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
        .padding(20.0)
        .frame(width: 680.0, height: 440.0)
        .onAppear {
            if selection == nil {
                selection = Dependency.all.first?.id
            }
        }
    }
}
