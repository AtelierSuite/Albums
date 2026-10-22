import Foundation
import SwiftUI
import UIKit

struct LabsFileEntry: Identifiable, Hashable {

    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64

    var id: String { url.path }

    static func sharedContainerRoot() -> LabsFileEntry? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tsubuzaki.IllustMate"
        ) else {
            return nil
        }
        return LabsFileEntry(url: url, name: url.lastPathComponent, isDirectory: true, size: 0)
    }

    func loadChildren() -> [LabsFileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: []
        ) else {
            return []
        }
        return urls.map { childURL in
            let values = try? childURL.resourceValues(forKeys: Set(keys))
            return LabsFileEntry(
                url: childURL,
                name: childURL.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

struct LabsFileExplorerView: View {

    @State private var rootEntries: [LabsFileEntry] = []

    var body: some View {
        List {
            if rootEntries.isEmpty {
                Text("Labs.FileExplorer.Empty", tableName: "More")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rootEntries) { entry in
                    LabsFileEntryRow(entry: entry)
                }
            }
        }
        .navigationTitle(String(localized: "Labs.FileExplorer", table: "More"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if rootEntries.isEmpty {
                rootEntries = LabsFileEntry.sharedContainerRoot()?.loadChildren() ?? []
            }
        }
    }
}

private struct LabsFileEntryRow: View {

    let entry: LabsFileEntry

    @State private var children: [LabsFileEntry] = []
    @State private var isExpanded: Bool = false
    @State private var didLoad: Bool = false
    @State private var isExportPresented: Bool = false

    var body: some View {
        if entry.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    LabsFileEntryRow(entry: child)
                }
            } label: {
                Label {
                    Text(entry.name)
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.accent)
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded, !didLoad {
                    children = entry.loadChildren()
                    didLoad = true
                }
            }
        } else {
            Button {
                isExportPresented = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2.0) {
                        Text(entry.name)
                        Text(entry.size.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isExportPresented) {
                DocumentExporter(url: entry.url)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct DocumentExporter: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
