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
                ContentUnavailableView {
                    Label(String(localized: "Photos.NoAccess.Title", table: "Saving", bundle: .engine),
                          systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("Photos.NoAccess.Message", tableName: "Saving", bundle: .engine)
                } actions: {
                    Button(role: .close) { session.cancel() }
                        .buttonStyle(.glass)
                }
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
                .navigationDestination(for: PhotosCollection.self) { collection in
                    if case .folder(let folder) = collection {
                        PhotosCollectionGrid(folder: folder, session: session,
                                             selectedIDs: $selectedIDs, selectedTitles: $selectedTitles)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
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
                    .padding(4.0)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 20.0)
            }
            .padding(.vertical, 12.0)
        }
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
            if folder == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { session.cancel() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newAlbumName = ""
                    isCreatingAlbum = true
                } label: {
                    Label(String(localized: "Photos.NewAlbum", table: "Saving", bundle: .engine),
                          systemImage: "rectangle.stack.badge.plus")
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
                .clipShape(.rect(cornerRadius: 12.0))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12.0)
                            .strokeBorder(.tint, lineWidth: 3.0)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .padding(6.0)
                    }
                }
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
        ContentUnavailableView {
            Label(String(localized: "Saving.NoItems.Title", table: "Saving", bundle: .engine),
                  systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Saving.NoItems.Message", tableName: "Saving", bundle: .engine)
        } actions: {
            Button(role: .close) { session.cancel() }
                .buttonStyle(.glass)
        }
    }
}
