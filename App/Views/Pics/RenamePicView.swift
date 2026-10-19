import Engine
import SwiftUI

struct RenamePicView: View {

    @Environment(\.dismiss) var dismiss
    @State var pic: Pic
    @State var newPicName: String = ""
    @FocusState var focusedField: FocusedField?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(pic.name, text: $newPicName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .newPicName)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        await DataActor.shared.renamePic(withID: pic.id, to: newPicName)
                        await MainActor.run {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Shared.Rename")
                        .bold()
                        .padding(4.0)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .disabled(newPicName.trimmingCharacters(in: .whitespaces) == "")
                .frame(maxWidth: .infinity)
                .padding(20.0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        newPicName = ""
                        dismiss()
                    }
                }
            }
            .navigationTitle("ViewTitle.Pics.Rename")
            .navigationBarTitleDisplayMode(.inline)
        }
#if targetEnvironment(macCatalyst)
        .defaultFocus($focusedField, .newPicName)
#else
        .onAppear {
            focusedField = .newPicName
        }
#endif
        .task {
            newPicName = pic.name
        }
        .phonePresentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    enum FocusedField {
        case newPicName
    }
}
