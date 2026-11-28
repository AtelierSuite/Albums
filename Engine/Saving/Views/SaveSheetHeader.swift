#if os(macOS)
import SwiftUI

public struct SaveSheetHeader<Actions: View>: View {

    var title: Text
    var showsBack: Bool
    var searchText: Binding<String>?
    var searchPrompt: Text?
    var onClose: (() -> Void)?
    var actions: () -> Actions

    @Environment(\.dismiss) private var dismiss

    public init(title: Text, showsBack: Bool = false, searchText: Binding<String>? = nil,
                searchPrompt: Text? = nil, onClose: (() -> Void)? = nil,
                @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.showsBack = showsBack
        self.searchText = searchText
        self.searchPrompt = searchPrompt
        self.onClose = onClose
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10.0) {
            HStack(spacing: 8.0) {
                if showsBack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                }
                title
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                actions()
                if let onClose {
                    Button(role: .close, action: onClose)
                }
            }
            .buttonStyle(.borderless)
            if let searchText {
                TextField(text: searchText, prompt: searchPrompt) {
                    EmptyView()
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 16.0)
        .padding(.vertical, 12.0)
    }
}
#endif
