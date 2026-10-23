import Photos
import SwiftUI

public struct PhotosSaveView: View {

    var session: SaveSession

    @State private var isAuthorized: Bool?
    @State private var path: [PhotosCollection] = []
    @State private var selectedIDs: [String] = []
    @State private var selectedTitles: [String: String] = [:]

    public init(session: SaveSession) {
        self.session = session
    }

    public var body: some View {
        ZStack {
            switch isAuthorized {
            case .none:
                ProgressView()
            case .some(false):
                SaveErrorView(session: session,
                              title: String(localized: "Photos.NoAccess.Title", table: "Saving", bundle: .engine),
                              message: String(localized: "Photos.NoAccess.Message", table: "Saving", bundle: .engine),
                              systemImage: "photo.badge.exclamationmark")
            case .some(true):
                if session.items.isEmpty {
                    NothingToSaveView(session: session)
                } else {
                    picker
                }
            }
            SaveSessionOverlay(session: session)
        }
        .task {
            isAuthorized = await PhotosSaver.authorize()
        }
    }

    private var picker: some View {
        NavigationStack(path: $path) {
            PhotosCollectionGrid(folder: nil, session: session,
                                 selectedIDs: $selectedIDs, selectedTitles: $selectedTitles)
                .safeAreaBar(edge: .bottom) { saveBar }
                .navigationDestination(for: PhotosCollection.self) { collection in
                    if case .folder(let folder) = collection {
                        PhotosCollectionGrid(folder: folder, session: session,
                                             selectedIDs: $selectedIDs, selectedTitles: $selectedTitles)
                            .safeAreaBar(edge: .bottom) { saveBar }
                    }
                }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 12.0) {
            SharedItemsStrip(items: session.items)
            Button {
                let destination = SaveDestination.photos(
                    collectionIDs: selectedIDs,
                    titles: selectedIDs.compactMap { selectedTitles[$0] }
                )
                Task { await session.save(to: destination) }
            } label: {
                Group {
                    if selectedIDs.isEmpty {
                        Text("Photos.SaveToLibrary", tableName: "Saving", bundle: .engine)
                    } else {
                        Text("Photos.SaveToSelected.\(selectedIDs.count)", tableName: "Saving", bundle: .engine)
                    }
                }
                .bold()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .buttonSizing(.flexible)
            .padding(.horizontal, 20.0)
        }
        .padding(.vertical, 12.0)
    }
}

struct PhotosCollectionGrid: View {

    var folder: PHCollectionList?
    var session: SaveSession
    @Binding var selectedIDs: [String]
    @Binding var selectedTitles: [String: String]

    @State private var collections: [PhotosCollection] = []
    @State private var searchText: String = ""
    @State private var isCreatingAlbum: Bool = false
    @State private var newAlbumName: String = ""

    private var displayedCollections: [PhotosCollection] {
        searchText.isEmpty ? collections : PhotosSaver.albums(matching: searchText)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96.0, maximum: 140.0), spacing: 16.0)],
                      spacing: 16.0) {
                ForEach(displayedCollections) { collection in
                    switch collection {
                    case .album(let album):
                        Button {
                            toggle(album)
                        } label: {
                            PhotosCollectionCell(collection: collection,
                                                 isSelected: selectedIDs.contains(album.localIdentifier))
                        }
                        .buttonStyle(.plain)
                    case .folder:
                        NavigationLink(value: collection) {
                            PhotosCollectionCell(collection: collection, isSelected: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20.0)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .overlay {
            if displayedCollections.isEmpty {
                ContentUnavailableView(String(localized: "Photos.Empty", table: "Saving", bundle: .engine),
                                       systemImage: "rectangle.stack")
            }
        }
        .navigationTitle(folder?.localizedTitle ?? String(localized: "Destination.Photos", table: "Saving",
                                                          bundle: .engine))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Photos.Search.Prompt", tableName: "Saving", bundle: .engine))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    newAlbumName = ""
                    isCreatingAlbum = true
                } label: {
                    Label(String(localized: "Photos.NewAlbum", table: "Saving", bundle: .engine),
                          systemImage: "rectangle.stack.badge.plus")
                }
            }
            if folder == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { session.cancel() }
                }
            }
        }
        .alert(String(localized: "Photos.NewAlbum", table: "Saving", bundle: .engine),
               isPresented: $isCreatingAlbum) {
            TextField(String(localized: "Photos.NewAlbum.Placeholder", table: "Saving", bundle: .engine),
                      text: $newAlbumName)
            Button(String(localized: "Photos.Create", table: "Saving", bundle: .engine)) {
                createAlbum()
            }
            Button(role: .cancel) { }
        }
        .task {
            collections = PhotosSaver.collections(in: folder)
        }
    }

    private func toggle(_ album: PHAssetCollection) {
        let identifier = album.localIdentifier
        withAnimation(.smooth.speed(2.0)) {
            if let index = selectedIDs.firstIndex(of: identifier) {
                selectedIDs.remove(at: index)
            } else {
                selectedIDs.append(identifier)
                selectedTitles[identifier] = album.localizedTitle ?? ""
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func createAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            try? await PhotosSaver.createAlbum(named: name, in: folder)
            collections = PhotosSaver.collections(in: folder)
            if case .album(let album) = collections.first(where: { $0.title == name }),
               !selectedIDs.contains(album.localIdentifier) {
                toggle(album)
            }
        }
    }
}

struct PhotosCollectionCell: View {

    var collection: PhotosCollection
    var isSelected: Bool

    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Color.secondary.opacity(0.15)
                .aspectRatio(1.0, contentMode: .fit)
                .overlay {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: isFolder ? "folder.fill" : "photo.on.rectangle")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if !isFolder {
                        SelectionOverlay(isSelected)
                    }
                }
                .clipShape(.rect(cornerRadius: 12.0))
            Text(collection.title)
                .font(.caption)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .task(id: collection.id) {
            guard let identifier = PhotosSaver.coverAssetIdentifier(for: collection) else { return }
            cover = await PhotosSaver.thumbnail(forAssetWithIdentifier: identifier, length: 240.0)
        }
    }

    private var isFolder: Bool {
        if case .folder = collection { return true }
        return false
    }
}

public struct NothingToSaveView: View {

    var session: SaveSession

    public init(session: SaveSession) {
        self.session = session
    }

    public var body: some View {
        SaveErrorView(session: session,
                      title: String(localized: "Saving.NoItems.Title", table: "Saving", bundle: .engine),
                      message: String(localized: "Saving.NoItems.Message", table: "Saving", bundle: .engine),
                      systemImage: "photo.badge.exclamationmark")
    }
}
