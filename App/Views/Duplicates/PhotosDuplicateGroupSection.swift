import Engine
import Photos
import SwiftUI

struct PhotosDuplicateGroupSection: View {

    let group: PhotosDuplicateGroup
    @Binding var selectedForDeletion: Set<String>
    var onDelete: (Set<String>) -> Void

    @State var comparisonViewerManager = PhotosViewerManager()
    @State var isShowingComparison: Bool = false
    @State var isConfirmingDelete: Bool = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12.0) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        PhotosDuplicateDetailCard(
                            asset: asset,
                            isSelectedForDeletion: selectedForDeletion.contains(asset.localIdentifier)
                        ) {
                            withAnimation(.smooth.speed(2.0)) {
                                if selectedForDeletion.contains(asset.localIdentifier) {
                                    selectedForDeletion.remove(asset.localIdentifier)
                                } else {
                                    if selectedForDeletion.count < group.assets.count - 1 {
                                        selectedForDeletion.insert(asset.localIdentifier)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4.0)
                .padding(.horizontal, 18.0)
            }
            .listRowInsets(EdgeInsets(top: 14.0, leading: 0, bottom: 14.0, trailing: 0))
            Button(String(localized: "Duplicates.CompareInCarousel", table: "Photos")) {
                let firstAsset = group.assets[0]
                comparisonViewerManager.setDisplay(firstAsset, in: group.assets)
                isShowingComparison = true
            }
            .tint(.accent)
            if !selectedForDeletion.isEmpty {
                Button(String(localized: "Duplicates.DeleteSelected.\(selectedForDeletion.count)", table: "Photos"),
                       role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        } header: {
            Text("Duplicates.GroupCount.\(group.assets.count)", tableName: "Photos")
        }
        .alert(
            "Shared.DeleteConfirmation.Photo.\(selectedForDeletion.count)",
            isPresented: $isConfirmingDelete
        ) {
            Button("Shared.Yes", role: .destructive) {
                Task {
                    let idsToDelete = selectedForDeletion
                    let deleted = await deletePhotosAssets(withIdentifiers: Array(idsToDelete))
                    guard deleted else { return }
                    for assetID in idsToDelete {
                        await HashActor.shared.deleteHash(forPicWithID: assetID)
                    }
                    await MainActor.run {
                        withAnimation(.smooth.speed(2.0)) {
                            onDelete(idsToDelete)
                        }
                    }
                    selectedForDeletion = []
                }
            }
            Button("Shared.No", role: .cancel) {}
        }
        .navigationDestination(isPresented: $isShowingComparison) {
            PhotosAssetViewer(asset: group.assets[0])
                .environment(comparisonViewerManager)
        }
    }
}
