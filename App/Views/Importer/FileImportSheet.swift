import SwiftUI
import UniformTypeIdentifiers

struct FileImportModifier: ViewModifier {
    @Binding var isFileImporterPresented: Bool
    @Binding var isFileImportSheetPresented: Bool
    var onFilesImported: ([(filename: String, data: Data)]) -> Void

    func body(content: Content) -> some View {
        content
            #if targetEnvironment(macCatalyst)
            .sheet(isPresented: $isFileImportSheetPresented) {
                FileImportSheet(allowedContentTypes: [.image, .movie],
                                        onFilesImported: onFilesImported)
            }
            #else
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    var loadedFiles: [(filename: String, data: Data)] = []
                    for url in urls {
                        let didStartAccessing = url.startAccessingSecurityScopedResource()
                        if let data = try? Data(contentsOf: url) {
                            loadedFiles.append((filename: url.lastPathComponent, data: data))
                        }
                        if didStartAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    onFilesImported(loadedFiles)
                case .failure:
                    break
                }
            }
            #endif
    }
}

#if targetEnvironment(macCatalyst)

struct FileImportSheet: View {

    @Environment(\.dismiss) var dismiss

    var allowedContentTypes: [UTType]
    var onFilesImported: ([(filename: String, data: Data)]) -> Void

    @State private var isFileImporterPresented: Bool = false
    @State private var selectedURLs: [URL] = []
    @State private var didPickFiles: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16.0) {
                    if selectedURLs.isEmpty {
                        if didPickFiles {
                            Text("Import.NoFilesSelected", tableName: "Import")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        ForEach(selectedURLs, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20.0)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12.0) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Text("Import.SelectFromFiles", tableName: "Import")
                            .bold()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .buttonSizing(.flexible)

                    Button {
                        var loadedFiles: [(filename: String, data: Data)] = []
                        for url in selectedURLs {
                            let didStartAccessing = url.startAccessingSecurityScopedResource()
                            if let data = try? Data(contentsOf: url) {
                                loadedFiles.append((filename: url.lastPathComponent, data: data))
                            }
                            if didStartAccessing {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        onFilesImported(loadedFiles)
                        dismiss()
                    } label: {
                        Text("Import.StartImport", tableName: "Import")
                            .bold()
                    }
                    .tint(.accent)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .buttonSizing(.flexible)
                    .disabled(selectedURLs.isEmpty)
                }
                .padding(20.0)
            }
            .navigationTitle("ViewTitle.Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            didPickFiles = true
            switch result {
            case .success(let urls):
                selectedURLs = urls
            case .failure:
                break
            }
        }
        .onAppear {
            isFileImporterPresented = true
        }
    }
}
#endif
