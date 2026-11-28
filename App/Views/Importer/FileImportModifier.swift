import SwiftUI
import UniformTypeIdentifiers

struct FileImportModifier: ViewModifier {
    @Binding var isFileImporterPresented: Bool
    var onFilesImported: ([(filename: String, data: Data)]) -> Void

    func body(content: Content) -> some View {
        content
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
    }
}

