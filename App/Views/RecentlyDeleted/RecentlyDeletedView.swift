import Engine
import SwiftUI

struct RecentlyDeletedView: View {

    enum PermanentDeletion: Identifiable {
        case pics([String])
        case all

        var id: String {
            switch self {
            case .pics(let ids): "pics-" + ids.joined(separator: ",")
            case .all: "all"
            }
        }
    }

    @EnvironmentObject var navigation: NavigationManager

    @State var pics: [Pic] = []
    @State var hasFetchedPics: Bool = false
    @State var isSelecting: Bool = false
    @State var selectedIDs: Set<String> = []
    @State var pendingDeletion: PermanentDeletion?

    private let columnCount: Int = 4

    var body: some View {
        content
            .navigationTitle(Text("RecentlyDeleted.Title", tableName: "Albums"))
            .toolbar {
                toolbarContent
            }
            .alert(
                Text("RecentlyDeleted.DeleteConfirmation.\(pendingDeletionCount)", tableName: "Albums"),
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { deletion in
                Button(String(localized: "RecentlyDeleted.DeletePermanently", table: "Albums"),
                       role: .destructive) {
                    permanentlyDelete(deletion)
                }
                Button("Shared.Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { _ in
                Text("RecentlyDeleted.DeleteConfirmation.Message", tableName: "Albums")
            }
            .task {
                await RecentlyDeleted.purgeExpired(in: DataActor.shared.collectionID)
                await refresh()
            }
            .onChange(of: navigation.dataVersion) { _, _ in
                Task {
                    await refresh()
                }
            }
    }

    @ViewBuilder
    var content: some View {
        if hasFetchedPics && pics.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "RecentlyDeleted.Empty", table: "Albums"), systemImage: "trash")
            } description: {
                Text("RecentlyDeleted.Description", tableName: "Albums")
            }
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12.0) {
                    Text("RecentlyDeleted.Description", tableName: "Albums")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20.0)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0),
                                             count: columnCount),
                              spacing: 2.0) {
                        ForEach(pics) { pic in
                            cell(for: pic)
                        }
                    }
                }
                .padding(.top, 20.0)
            }
        }
    }

    func cell(for pic: Pic) -> some View {
        PicLabel(pic: pic)
            .overlay(alignment: .bottomLeading) {
                Text("RecentlyDeleted.DaysRemaining.\(RecentlyDeleted.daysRemaining(for: pic))",
                     tableName: "Albums")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6.0)
                    .padding(.vertical, 2.0)
                    .background(.black.opacity(0.6), in: .capsule)
                    .padding(4.0)
            }
            .overlay {
                if isSelecting {
                    SelectionOverlay(selectedIDs.contains(pic.id))
                }
            }
            .contentShape(.rect)
            .accessibilityIdentifier("pic:\(pic.name)")
            .onTapGesture {
                guard isSelecting else { return }
                if selectedIDs.contains(pic.id) {
                    selectedIDs.remove(pic.id)
                } else {
                    selectedIDs.insert(pic.id)
                }
            }
            .contextMenu {
                if !isSelecting {
                    Button(String(localized: "RecentlyDeleted.Recover", table: "Albums"),
                           systemImage: "arrow.uturn.backward") {
                        restore([pic.id])
                    }
                    Button(String(localized: "RecentlyDeleted.DeletePermanently", table: "Albums"),
                           systemImage: "trash", role: .destructive) {
                        pendingDeletion = .pics([pic.id])
                    }
                }
            }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    stopSelecting()
                } label: {
                    Image(systemName: "xmark")
                }
            } else {
                Button("Shared.Select") {
                    withAnimation(.smooth.speed(2.0)) {
                        isSelecting = true
                    }
                }
                .disabled(pics.isEmpty)
            }
        }
        ToolbarItemGroup(placement: actionPlacement) {
            if isSelecting {
                Button(String(localized: "RecentlyDeleted.Recover", table: "Albums"),
                       systemImage: "arrow.uturn.backward") {
                    restore(Array(selectedIDs))
                }
                .disabled(selectedIDs.isEmpty)
                Text("Shared.Selected.\(selectedIDs.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize()
                Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                    pendingDeletion = .pics(Array(selectedIDs))
                }
                .disabled(selectedIDs.isEmpty)
                .tint(.red)
            } else {
                Button(String(localized: "RecentlyDeleted.RecoverAll", table: "Albums")) {
                    restore(pics.map(\.id))
                }
                .disabled(pics.isEmpty)
                Button(String(localized: "RecentlyDeleted.DeleteAll", table: "Albums"), role: .destructive) {
                    pendingDeletion = .all
                }
                .disabled(pics.isEmpty)
                .tint(.red)
            }
        }
    }

    private var actionPlacement: ToolbarItemPlacement {
#if targetEnvironment(macCatalyst)
        .topBarTrailing
#else
        .bottomBar
#endif
    }

    private var pendingDeletionCount: Int {
        switch pendingDeletion {
        case .pics(let ids): ids.count
        case .all: pics.count
        case nil: 0
        }
    }

    func refresh() async {
        let fetched = (try? await DataActor.shared.recentlyDeletedPics()) ?? []
        // Animating into the empty state leaves the navigation bar's large title hidden.
        withAnimation(fetched.isEmpty ? nil : .smooth.speed(2.0)) {
            pics = fetched
            selectedIDs.formIntersection(fetched.map(\.id))
        }
        hasFetchedPics = true
    }

    func stopSelecting() {
        withAnimation(.smooth.speed(2.0)) {
            isSelecting = false
            selectedIDs.removeAll()
        }
    }

    func restore(_ ids: [String]) {
        let idSet = Set(ids)
        let albumIDs = Set(pics.filter { idSet.contains($0.id) }.compactMap(\.containingAlbumID))
        Task {
            await DataActor.shared.restoreFromRecentlyDeleted(picIDs: ids)
            for albumID in albumIDs {
                AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
            }
            stopSelecting()
            navigation.signalDataChanged()
        }
    }

    func permanentlyDelete(_ deletion: PermanentDeletion) {
        pendingDeletion = nil
        Task {
            let collectionID = DataActor.shared.collectionID
            let ids: [String]
            switch deletion {
            case .pics(let selected): ids = selected
            case .all: ids = await DataActor.shared.allRecentlyDeletedPicIDs()
            }
            await RecentlyDeleted.permanentlyDelete(picIDs: ids, in: collectionID)
            stopSelecting()
            navigation.signalDataChanged()
        }
    }
}
