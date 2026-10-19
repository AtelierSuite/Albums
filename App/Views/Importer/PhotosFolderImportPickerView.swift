import Engine
import Photos
import SwiftUI

struct PhotosFolderImportPickerView: View {

    var folder: PHCollectionList?
    var selectedAlbum: Album?
    var onDismiss: () -> Void

    @State var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State var items: [PHCollectionItem] = []
    @State var hasFetched: Bool = false

    @State var isImporting: Bool = false
    @State var isImportCompleted: Bool = false
    @State var importCurrentCount: Int = 0
    @State var importTotalCount: Int = 0
    @State var importCompletedCount: Int = 0

    var body: some View {
        Group {
            if isImportCompleted {
                VStack {
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
                }
            } else if isImporting {
                StatusView(type: .inProgress, title: .importImporting,
                           currentCount: importCurrentCount, totalCount: importTotalCount)
            } else if folder != nil {
                folderListView
            } else {
                switch authorizationStatus {
                case .authorized, .limited:
                    folderListView
                case .denied, .restricted:
                    deniedView
                default:
                    ProgressView()
                        .task {
                            await requestAuthorization()
                        }
                }
            }
        }
        .navigationTitle(
            folder == nil
            ? String(localized: "Import.Albums", table: "Import")
            : (folder?.localizedTitle ?? String(localized: "Import.Albums.Untitled", table: "Import"))
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isImporting || isImportCompleted)
        .navigationDestination(for: PHCollectionListWrapper.self) { wrapper in
            PhotosFolderImportPickerView(
                folder: wrapper.collectionList,
                selectedAlbum: selectedAlbum,
                onDismiss: onDismiss
            )
        }
    }

    var deniedView: some View {
        VStack(spacing: 16.0) {
            Image(systemName: "photo.badge.exclamationmark")
                .resizable()
                .scaledToFit()
                .frame(width: 64.0, height: 64.0)
                .foregroundStyle(.secondary)
            Text("Import.PhotosAccessDenied", tableName: "Import")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "Import.OpenSettings", table: "Import")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(40.0)
    }
}
