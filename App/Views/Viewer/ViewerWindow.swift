import Engine
import Photos
import SwiftUI

let openPicsInNewWindowKey = "OpenPicsInNewWindow"

enum ViewerWindowValue: Codable, Hashable {
    case pic(selectedID: String, siblingIDs: [String])
    case photo(selectedID: String, siblingIDs: [String])
}

struct ViewerWindowContent: View {

    let value: ViewerWindowValue

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
        }
        .environment(viewer)
        .environment(photosViewer)
        .task {
            await load()
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
