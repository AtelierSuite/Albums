import Engine
import SwiftUI

struct LibraryCoverPickerView: View {

    @Environment(\.dismiss) var dismiss

    var library: PicLibrary
    var onSave: () -> Void

    @State private var pics: [Pic] = []
    @State private var selectedPicIDs: [String] = []
    @State private var isLoaded: Bool = false

    private var dataActor: DataActor {
        DataActor.instance(for: library.id)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isLoaded {
                    ProgressView()
                } else if pics.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Albums.Empty", table: "Albums"),
                        systemImage: "photo.on.rectangle.angled"
                    )
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: 4),
                                  spacing: 2.0) {
                            ForEach(pics) { pic in
                                Button {
                                    toggle(pic)
                                } label: {
                                    LibraryCoverPickerCell(
                                        pic: pic,
                                        dataActor: dataActor,
                                        isSelected: selectedPicIDs.contains(pic.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Libraries.Cover.Instructions", tableName: "Libraries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8.0)
            }
            .navigationTitle(String(localized: "Libraries.Cover.Title", table: "Libraries"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        save(selectedPicIDs)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(String(localized: "Libraries.Cover.Reset", table: "Libraries")) {
                        save([])
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func toggle(_ pic: Pic) {
        if let index = selectedPicIDs.firstIndex(of: pic.id) {
            selectedPicIDs.remove(at: index)
        } else if selectedPicIDs.count < LibraryCoverCache.maximumCoverCount {
            selectedPicIDs.append(pic.id)
        }
    }

    private func save(_ picIDs: [String]) {
        let libraryID = library.id
        Task {
            await LibrariesActor.shared.setCoverPicIDs(picIDs, forID: libraryID)
            onSave()
            await SyncManager.shared.pushLibraryChanges()
        }
        dismiss()
    }

    private func load() async {
        let libraryID = library.id
        let loadedPics = (try? await dataActor.allPicSkeletons()) ?? []
        let savedIDs = await LibrariesActor.shared.coverPicIDs(forID: libraryID)
        let availableIDs = Set(loadedPics.map(\.id))
        pics = loadedPics
        selectedPicIDs = savedIDs.filter { availableIDs.contains($0) }
        isLoaded = true
    }
}

struct LibraryCoverPickerCell: View {

    var pic: Pic
    var dataActor: DataActor
    var isSelected: Bool

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .aspectRatio(1.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(.rect(cornerRadius: 4.0))
            .overlay {
                SelectionOverlay(isSelected)
            }
            .contentShape(.rect)
            .task(id: pic.id) {
                let picID = pic.id
                let data = await dataActor.thumbnailData(forPicWithID: picID)
                image = data.flatMap { UIImage(data: $0) }
            }
    }
}
