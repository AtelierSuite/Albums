import Engine
import SwiftUI

struct DuplicateResultsView: View {

    var scanManager: DuplicateScanManager

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
                    DuplicateGroupSection(
                        group: group,
                        dataActor: scanManager.dataActor,
                        selectedForDeletion: Binding(
                            get: { selectedForDeletion[group.id] ?? [] },
                            set: { selectedForDeletion[group.id] = $0 }
                        )
                    ) { deletedIDs in
                        scanManager.removePics(withIDs: deletedIDs)
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
                "Shared.DeleteConfirmation.Pic.\(allSelectedIDs.count)",
                isPresented: $isConfirmingDeleteAll
            ) {
                Button("Shared.Yes", role: .destructive) {
                    Task {
                        let idsToDelete = allSelectedIDs
                        let dataActor = scanManager.dataActor
                        for picID in idsToDelete {
                            await dataActor.deletePic(withID: picID)
                            await HashActor.shared.deleteHash(forPicWithID: picID)
                        }
                        let collectionID = dataActor.collectionID
                        Task.detached {
                            await OriginalsManager.shared.deleteCloudOriginals(
                                picIDs: Array(idsToDelete), in: collectionID
                            )
                        }
                        await MainActor.run {
                            withAnimation(.smooth.speed(2.0)) {
                                scanManager.removePics(withIDs: idsToDelete)
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

// MARK: - Group Section

struct DuplicateGroupSection: View {

    let group: DuplicateGroup
    var dataActor: DataActor
    @Binding var selectedForDeletion: Set<String>
    var onDelete: (Set<String>) -> Void

    @State var comparisonViewerManager = ViewerManager()
    @State var isShowingComparison: Bool = false
    @State var isConfirmingDelete: Bool = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12.0) {
                    ForEach(group.pics) { pic in
                        DuplicateDetailCard(
                            pic: pic,
                            dataActor: dataActor,
                            isSelectedForDeletion: selectedForDeletion.contains(pic.id)
                        ) {
                            withAnimation(.smooth.speed(2.0)) {
                                if selectedForDeletion.contains(pic.id) {
                                    selectedForDeletion.remove(pic.id)
                                } else {
                                    if selectedForDeletion.count < group.pics.count - 1 {
                                        selectedForDeletion.insert(pic.id)
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
                let firstPic = group.pics[0]
                comparisonViewerManager.setDisplay(firstPic, in: group.pics) {
                    isShowingComparison = true
                }
            }
            .tint(.accent)
            if !selectedForDeletion.isEmpty {
                Button(String(localized: "Duplicates.DeleteSelected.\(selectedForDeletion.count)", table: "Photos"),
                       role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        } header: {
            Text("Duplicates.GroupCount.\(group.pics.count)", tableName: "Photos")
        }
        .alert(
            "Shared.DeleteConfirmation.Pic.\(selectedForDeletion.count)",
            isPresented: $isConfirmingDelete
        ) {
            Button("Shared.Yes", role: .destructive) {
                Task {
                    for picID in selectedForDeletion {
                        await dataActor.deletePic(withID: picID)
                        await HashActor.shared.deleteHash(forPicWithID: picID)
                    }
                    let collectionID = dataActor.collectionID
                    let idsForCleanup = Array(selectedForDeletion)
                    Task.detached {
                        await OriginalsManager.shared.deleteCloudOriginals(
                            picIDs: idsForCleanup, in: collectionID
                        )
                    }
                    await MainActor.run {
                        withAnimation(.smooth.speed(2.0)) {
                            onDelete(selectedForDeletion)
                        }
                    }
                    selectedForDeletion = []
                }
            }
            Button("Shared.No", role: .cancel) {}
        }
        .navigationDestination(isPresented: $isShowingComparison) {
            PicViewer(pic: group.pics[0])
                .environment(comparisonViewerManager)
        }
    }
}
