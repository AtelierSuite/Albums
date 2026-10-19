import Engine
import Photos
import SwiftUI

struct PhotosDuplicateResultsView: View {

    var scanManager: PhotosDuplicateScanManager

    @State var selectedForDeletion: [UUID: Set<String>] = [:]
    @State var isConfirmingDeleteAll: Bool = false

    var allSelectedIDs: Set<String> {
        selectedForDeletion.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    var groupsWithSelections: Int {
        selectedForDeletion.values.filter { !$0.isEmpty }.count
    }

    var body: some View {
        if scanManager.duplicateGroups.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "Duplicates.NoDuplicatesFound", table: "Photos"),
                      systemImage: "checkmark.circle")
            } description: {
                Text("Duplicates.NoDuplicatesFound.Message", tableName: "Photos")
            }
        } else {
            List {
                ForEach(scanManager.duplicateGroups) { group in
                    PhotosDuplicateGroupSection(
                        group: group,
                        selectedForDeletion: Binding(
                            get: { selectedForDeletion[group.id] ?? [] },
                            set: { selectedForDeletion[group.id] = $0 }
                        )
                    ) { deletedIDs in
                        scanManager.removeAssets(withIDs: deletedIDs)
                        selectedForDeletion[group.id] = nil
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(
                            localized: "Duplicates.DeleteAllSelected.\(allSelectedIDs.count)",
                            table: "Photos"
                        ),
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        isConfirmingDeleteAll = true
                    }
                    .tint(.red)
                    .disabled(groupsWithSelections == 0)
                }
            }
            .alert(
                "Shared.DeleteConfirmation.Photo.\(allSelectedIDs.count)",
                isPresented: $isConfirmingDeleteAll
            ) {
                Button("Shared.Yes", role: .destructive) {
                    Task {
                        let idsToDelete = allSelectedIDs
                        let deleted = await deletePhotosAssets(withIdentifiers: Array(idsToDelete))
                        guard deleted else { return }
                        for assetID in idsToDelete {
                            await HashActor.shared.deleteHash(forPicWithID: assetID)
                        }
                        await MainActor.run {
                            withAnimation(.smooth.speed(2.0)) {
                                scanManager.removeAssets(withIDs: idsToDelete)
                                selectedForDeletion = [:]
                            }
                        }
                    }
                }
                Button("Shared.No", role: .cancel) {}
            }
        }
    }
}

// MARK: - Photos Deletion Helper

nonisolated func deletePhotosAssets(withIdentifiers identifiers: [String]) async -> Bool {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
    do {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        return true
    } catch {
        debugPrint("Failed to delete photos assets: \(error)")
        return false
    }
}
