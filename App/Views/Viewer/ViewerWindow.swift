import Engine
import Photos
import SwiftUI

enum ViewerWindowValue: Codable, Hashable {
    case pic(selectedID: String, siblingIDs: [String])
    case photo(selectedID: String, siblingIDs: [String])
}

struct ViewerWindowContent: View {

    let value: ViewerWindowValue
    var onDisplayedIDChange: ((String) -> Void)?

    @State private var viewer = ViewerManager(allowsShowInAlbum: false)
    @State private var photosViewer = PhotosViewerManager()
    @State private var hasLoaded: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                switch value {
                case .pic:
                    if let pic = viewer.displayedPic {
                        PicViewer(pic: pic)
                            .id(pic.id)
                    } else {
                        ProgressView()
                    }
                case .photo:
                    if let asset = photosViewer.displayedAsset {
                        PhotosAssetViewer(asset: asset)
                            .id(asset.localIdentifier)
                    } else {
                        ProgressView()
                    }
                }
            }
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
        }
        .environment(viewer)
        .environment(photosViewer)
        .task {
            await load()
        }
        #if os(macOS)
        .modifier(ViewerNavigateCommandHandler(viewer: viewer, photosViewer: photosViewer))
        #endif
        .onChange(of: viewer.displayedPicID) { _, id in
            if !id.isEmpty {
                onDisplayedIDChange?(id)
            }
        }
        .onChange(of: photosViewer.displayedAsset?.localIdentifier) { _, id in
            if let id {
                onDisplayedIDChange?(id)
            }
        }
    }

    private func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        switch value {
        case let .pic(selectedID, siblingIDs):
            guard let pics = try? await DataActor.shared.pics(withIDs: siblingIDs),
                  let selected = pics.first(where: { $0.id == selectedID }) ?? pics.first else { return }
            viewer.setDisplay(selected, in: pics) { }
        case let .photo(selectedID, siblingIDs):
            let assets = Self.fetchAssets(withLocalIdentifiers: siblingIDs)
            guard let selected = assets.first(where: { $0.localIdentifier == selectedID }) ?? assets.first
            else { return }
            photosViewer.setDisplay(selected, in: assets)
        }
    }

    private static func fetchAssets(withLocalIdentifiers ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            byID[asset.localIdentifier] = asset
        }
        return ids.compactMap { byID[$0] }
    }
}

#if os(macOS)
private struct ViewerNavigateCommandHandler: ViewModifier {

    let viewer: ViewerManager
    let photosViewer: PhotosViewerManager

    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .viewerNavigateCommand)) { notification in
                guard appearsActive, let command = notification.object as? ViewerNavigateCommand else { return }
                switch command {
                case .previous:
                    viewer.navigateToPrevious()
                    photosViewer.navigateToPrevious()
                case .next:
                    viewer.navigateToNext()
                    photosViewer.navigateToNext()
                }
            }
    }
}
#endif
