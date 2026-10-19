import AVFoundation
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
    @State private var importCurrentCount: Int = 0
    @State private var importTotalCount: Int = 0
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
                StatusView(type: .inProgress, title: .importImporting,
                           currentCount: importCurrentCount, totalCount: importTotalCount)
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

    private func importVideoAsset(_ asset: PHAsset, filename: String) async {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .highQualityFormat

        let exportSession: AVAssetExportSession? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestExportSession(
                forVideo: asset,
                options: videoOptions,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                nonisolated(unsafe) let result = session
                continuation.resume(returning: result)
            }
        }

        guard let exportSession else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard (try? await exportSession.export(to: tempURL, as: .mov)) != nil,
              let videoData = try? Data(contentsOf: tempURL) else { return }

        let fileExtension = (filename as NSString).pathExtension.isEmpty
            ? "mov" : (filename as NSString).pathExtension.lowercased()

        await DataActor.shared.createVideo(
            filename,
            data: videoData,
            duration: asset.duration,
            fileExtension: fileExtension,
            inAlbumWithID: selectedAlbum?.id,
            dateAdded: asset.creationDate
        )
    }

    private func startImport() {
        let assetsToImport = assets.filter { selectedAssets.contains($0.localIdentifier) }
        isImporting = true
        importTotalCount = assetsToImport.count
        importCurrentCount = 0

        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true

            for asset in assetsToImport {
                let resources = PHAssetResource.assetResources(for: asset)
                let filename = resources.first?.originalFilename ?? Pic.newFilename()

                if asset.mediaType == .video {
                    await importVideoAsset(asset, filename: filename)
                } else {
                    let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                        imageManager.requestImageDataAndOrientation(
                            for: asset, options: requestOptions
                        ) { data, _, _, _ in
                            continuation.resume(returning: data)
                        }
                    }

                    if let data {
                        await DataActor.shared.createPic(
                            filename, data: data,
                            inAlbumWithID: selectedAlbum?.id,
                            dateAdded: asset.creationDate
                        )
                    }
                }

                await MainActor.run {
                    importCurrentCount += 1
                }
            }

            await MainActor.run {
                if let selectedAlbum {
                    AlbumCoverCache.shared.removeImages(forAlbumID: selectedAlbum.id)
                }
                UIApplication.shared.isIdleTimerDisabled = false
                importCompletedCount = assetsToImport.count
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                doWithAnimation {
                    isImportCompleted = true
                }
            }
        }
    }
}
