import Engine
import Photos
import SwiftUI

struct PhotosAssetGridView: View {

    let collection: PHAssetCollection
    var selectedAlbum: Album?
    var onDismiss: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var selectedAssets: Set<String> = []

    @State private var isImporting: Bool = false
    @State private var isImportCompleted: Bool = false
    @State private var importCompletedCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if isImportCompleted {
                StatusView(type: .success, title: .importCompleted(count: importCompletedCount))
                Button {
                    onDismiss()
                } label: {
                    Text("Shared.OK")
                        .bold()
                        .padding(4.0)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .padding(20.0)
            } else if isImporting {
                ImportStatusView()
                ImportCancelButton()
            } else {
                ScrollView {
                    let columns = [GridItem(.adaptive(minimum: 80), spacing: 2)]
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            PhotoGridCell(
                                asset: asset,
                                isSelected: selectedAssets.contains(asset.localIdentifier)
                            ) {
                                toggleAsset(asset)
                            }
                        }
                    }
                }

                VStack(alignment: .center, spacing: 16.0) {
                    Text("Import.SelectedPhotos.\(selectedAssets.count)", tableName: "Import")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        startImport()
                    } label: {
                        Text("Import.StartImport", tableName: "Import")
                            .bold()
                            .padding(4.0)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.accent)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(selectedAssets.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .padding(20.0)
            }
        }
        .navigationTitle(collection.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isImporting || isImportCompleted)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isImporting && !isImportCompleted {
                    Button {
                        if selectedAssets.count == assets.count {
                            selectedAssets.removeAll()
                        } else {
                            selectedAssets = Set(assets.map { $0.localIdentifier })
                        }
                    } label: {
                        Text(selectedAssets.count == assets.count ?
                             String(localized: "Import.DeselectAll", table: "Import") :
                                String(localized: "Import.SelectAll", table: "Import"))
                    }
                }
            }
        }
        .interactiveDismissDisabled(isImporting)
        .onAppear {
            if assets.isEmpty {
                fetchAssets()
            }
        }
    }

    // MARK: - Data

    private func fetchAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }
        assets = fetched
        // Select all by default for bulk import convenience
        selectedAssets = Set(fetched.map { $0.localIdentifier })
    }

    private func toggleAsset(_ asset: PHAsset) {
        if selectedAssets.contains(asset.localIdentifier) {
            selectedAssets.remove(asset.localIdentifier)
        } else {
            selectedAssets.insert(asset.localIdentifier)
        }
    }

    private func startImport() {
        let albumID = selectedAlbum?.id
        var job = ImportJob(
            libraryID: DataActor.shared.collectionID,
            destinationAlbumID: albumID,
            destinationAlbumName: selectedAlbum?.name
        )
        job.items = assets
            .filter { selectedAssets.contains($0.localIdentifier) }
            .map { asset in
                ImportItem(
                    source: .photosAsset(localIdentifier: asset.localIdentifier, isVideo: asset.mediaType == .video),
                    albumID: albumID
                )
            }
        isImporting = true
        Task {
            let result = await ImportManager.shared.run(job)
            if result.wasCancelled {
                onDismiss()
                return
            }
            importCompletedCount = result.importedCount
            doWithAnimation {
                isImportCompleted = true
            }
        }
    }
}
