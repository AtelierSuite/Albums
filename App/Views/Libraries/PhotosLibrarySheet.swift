import SwiftUI
import UIKit

struct PhotosLibrarySheet: View {

    @Environment(\.dismiss) var dismiss

    @AppStorage("PhotosModeEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isPhotosModeEnabled: Bool = false
    @AppStorage("PhotosNestedAlbumsEnabled", store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var isNestedAlbumsEnabled: Bool = false

    var dismissAll: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if UIDevice.current.userInterfaceIdiom != .phone, !isPhotosModeEnabled {
                    Section {
                        Button(String(localized: "Libraries.SetActive", table: "Libraries")) {
                            withAnimation(.smooth.speed(2.0)) {
                                isPhotosModeEnabled = true
                            }
                            dismissAll?()
                        }
                    }
                }
                Section {
                    Toggle(String(localized: "Experiments.NestedAlbums", table: "More"),
                           isOn: $isNestedAlbumsEnabled)
                    Button(String(localized: "Experiments.NestedAlbums.CopyPrefix", table: "More")) {
                        UIPasteboard.general.string = "▶︎ "
                    }
                    .tint(.primary)
                    .disabled(!isNestedAlbumsEnabled)
                } footer: {
                    Text("Experiments.NestedAlbums.Description", tableName: "More")
                }
            }
            .tint(.accent)
            .navigationTitle(String(localized: "PhotosMode", table: "More"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .phonePresentationDetents([.medium, .large])
    }
}
