import Engine
import SwiftUI

enum LibraryMovePayload: Identifiable {
    case album(Album)
    case pics([Pic])

    var id: String {
        switch self {
        case .album(let album): return "album-\(album.id)"
        case .pics(let pics): return "pics-" + pics.map(\.id).joined(separator: ",")
        }
    }

    var isAlbum: Bool {
        if case .album = self { return true }
        return false
    }
}

struct MoveToLibrarySheet: View {

    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss

    let payload: LibraryMovePayload
    let sourceID: String
    let onMoved: () -> Void

    enum MoveStep: Hashable {
        case library(String)
        case album(String, Album)
    }

    @State private var path: [MoveStep] = []
    @State private var pendingDownloadLibrary: PicLibrary?
    @State private var isMoving: Bool = false
    @State private var moveCompleted: Int = 0
    @State private var moveTotal: Int = 0
    @State private var moveError: LibraryMoveError?

    var otherLibraries: [PicLibrary] {
        libraryManager.libraries.filter { $0.id != sourceID }
    }

    var sourceIsICloud: Bool {
        libraryManager.libraries.first { $0.id == sourceID }?.syncEnabled ?? false
    }

    var body: some View {
        NavigationStack(path: $path) {
            libraryList
                .navigationTitle(Text("Move.SelectLibrary"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .cancel) {
                            dismiss()
                        }
                    }
                }
                .navigationDestination(for: MoveStep.self) { step in
                    switch step {
                    case .library(let id):
                        picker(libraryID: id, parentAlbum: nil)
                            .navigationTitle(displayName(forLibraryID: id))
                    case .album(let id, let album):
                        picker(libraryID: id, parentAlbum: album)
                            .navigationTitle(album.name)
                    }
                }
        }
        .interactiveDismissDisabled(isMoving)
        .overlay {
            if isMoving {
                movingOverlay
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryMoveProgress)) { note in
            if let total = note.userInfo?["total"] as? Int,
               let completed = note.userInfo?["completed"] as? Int {
                moveTotal = total
                moveCompleted = completed
            }
        }
        .onChange(of: isMoving) { _, moving in
            UIApplication.shared.isIdleTimerDisabled = moving
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert(Text("Move.DownloadAlert.Title"),
               isPresented: Binding(get: { pendingDownloadLibrary != nil },
                                    set: { if !$0 { pendingDownloadLibrary = nil } })) {
            Button("Shared.OK") {
                if let library = pendingDownloadLibrary {
                    pendingDownloadLibrary = nil
                    path.append(.library(library.id))
                }
            }
            Button("Shared.Cancel", role: .cancel) {
                pendingDownloadLibrary = nil
            }
        } message: {
            Text("Move.DownloadAlert.Message")
        }
        .alert(Text("Move.Error.Title"),
               isPresented: Binding(get: { moveError != nil },
                                    set: { if !$0 { moveError = nil } })) {
            Button("Shared.OK", role: .cancel) {
                moveError = nil
            }
        } message: {
            if case .originalsNotUploaded = moveError {
                Text("Move.Error.NotUploaded")
            } else if payload.isAlbum {
                Text("Move.Error.Album")
            } else {
                Text("Move.Error.Pics")
            }
        }
    }

    var libraryList: some View {
        List {
            if otherLibraries.isEmpty {
                Text("Move.NoOtherLibraries")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(otherLibraries) { library in
                    Button {
                        selectLibrary(library)
                    } label: {
                        HStack(spacing: 12.0) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(.secondary)
                            Text(libraryManager.displayName(for: library))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func picker(libraryID: String, parentAlbum: Album?) -> some View {
        LibraryAlbumPickerView(
            libraryID: libraryID,
            parentAlbum: parentAlbum,
            onOpen: { path.append(.album(libraryID, $0)) },
            onMoveHere: { execute(destinationID: libraryID, destinationAlbumID: parentAlbum?.id) }
        )
    }

    var movingOverlay: some View {
        ZStack {
            Color(uiColor: .systemBackground).opacity(0.9)
            VStack(spacing: 16.0) {
                if moveTotal > 0 {
                    ProgressView(value: Double(moveCompleted), total: Double(moveTotal))
                        .progressViewStyle(.linear)
                        .tint(.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Text("Move.Moving")
            }
            .frame(maxWidth: .infinity)
            .padding(40.0)
        }
        .ignoresSafeArea()
    }

    func displayName(forLibraryID id: String) -> String {
        if let library = libraryManager.libraries.first(where: { $0.id == id }) {
            return libraryManager.displayName(for: library)
        }
        return ""
    }

    func selectLibrary(_ library: PicLibrary) {
        if sourceIsICloud && !library.syncEnabled {
            pendingDownloadLibrary = library
        } else {
            path.append(.library(library.id))
        }
    }

    func execute(destinationID: String, destinationAlbumID: String?) {
        moveCompleted = 0
        moveTotal = 0
        isMoving = true
        Task {
            do {
                switch payload {
                case .album(let album):
                    try await LibraryMoveManager.shared.moveAlbum(
                        albumID: album.id, from: sourceID, to: destinationID,
                        destinationParentAlbumID: destinationAlbumID)
                case .pics(let pics):
                    try await LibraryMoveManager.shared.movePics(
                        picIDs: pics.map(\.id), from: sourceID, to: destinationID,
                        destinationAlbumID: destinationAlbumID)
                }
                await MainActor.run {
                    onMoved()
                    dismiss()
                    let libraryName = displayName(forLibraryID: destinationID)
                    switch payload {
                    case .album(let album):
                        ToastManager.shared.show(ToastItem(
                            message: String(localized: "Toast.MovedAlbumToLibrary.\(album.name)-\(libraryName)",
                                            table: "Photos")))
                    case .pics(let pics):
                        ToastManager.shared.show(ToastItem(
                            message: String(localized: "Toast.MovedToLibrary.\(pics.count)-\(libraryName)",
                                            table: "Photos")))
                    }
                }
            } catch {
                await MainActor.run {
                    isMoving = false
                    moveError = (error as? LibraryMoveError) ?? .transferFailed
                }
            }
        }
    }
}
