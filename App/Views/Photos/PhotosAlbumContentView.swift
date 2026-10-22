import Photos
import SwiftUI

struct PhotosAlbumContentView: View {

    @Environment(PhotosManager.self) var photosManager

    let collection: PHAssetCollection

    @Namespace var namespace

    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var hasFetched: Bool = false

    @State private var isDuplicateCheckerPresented: Bool = false

    @AppStorage(photosPicSortKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    private var picSort: PhotosPicSortType = .dateCreatedDescending

    private var assetCount: Int {
        fetchResult?.count ?? 0
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0.0) {
                PhotosPicsSectionHeader(count: assetCount) {
                    isDuplicateCheckerPresented = true
                }

                if !hasFetched {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(20.0)
                } else if let fetchResult, fetchResult.count > 0 {
                    PhotosFetchResultAssetsGrid(namespace: namespace, fetchResult: fetchResult)
                } else {
                    Text("Albums.NoPics", tableName: "Albums")
                        .foregroundStyle(.secondary)
                        .padding(20.0)
                }
            }
            .padding([.top], 20.0)
        }
        .navigationTitle(collection.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
        .toolbar {
            if UIDevice.current.userInterfaceIdiom == .phone {
                ToolbarItemGroup(placement: .bottomBar) {
                    photosFilterMenu
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
        }
        .sheet(isPresented: $isDuplicateCheckerPresented) {
            PhotosDuplicateScanView(collection: collection)
                .phonePresentationDetents([.medium, .large])
                .interactiveDismissDisabled()
        }
        .onChange(of: isDuplicateCheckerPresented) { _, isPresented in
            if !isPresented {
                fetchAssets()
            }
        }
        .onChange(of: picSort) { _, _ in
            fetchAssets()
        }
        .onAppear {
            if !hasFetched {
                fetchAssets()
                hasFetched = true
            }
        }
    }

    private func fetchAssets() {
        fetchResult = photosManager.fetchAssets(in: collection, ascending: picSort.isAscending)
    }

    @ViewBuilder
    private var photosFilterMenu: some View {
        Menu {
            Button(String(localized: "Duplicates.FindDuplicates", table: "Photos"), systemImage: "photo.stack") {
                isDuplicateCheckerPresented = true
            }
            Section(String(localized: "Albums.Pics", table: "Albums")) {
                PhotosPicOptions()
            }
        } label: {
            Label("Shared.Filter", systemImage: "line.3.horizontal.decrease")
        }
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }
}
