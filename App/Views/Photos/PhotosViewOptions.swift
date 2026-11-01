import SwiftUI

let photosAlbumViewStyleKey = "PhotosAlbumViewStyle"
let photosAlbumSortKey = "PhotosAlbumSort"
let photosAlbumColumnCountKey = "PhotosAlbumColumnCount"
let photosPicViewStyleKey = "PhotosPicViewStyle"
let photosPicSortKey = "PhotosPicSort"
let photosPicColumnCountKey = "PhotosPicColumnCount"

enum PhotosPicSortType: String {
    case dateCreatedAscending
    case dateCreatedDescending

    var isAscending: Bool {
        self == .dateCreatedAscending
    }
}

struct PhotosPicSortPicker: View {

    @Binding var selection: PhotosPicSortType

    var body: some View {
        SortMenu(
            field: .constant(0),
            isAscending: Binding {
                selection.isAscending
            } set: {
                selection = $0 ? .dateCreatedAscending : .dateCreatedDescending
            }
        ) {
            Text("Shared.Sort.DateCreated")
                .tag(0)
        }
    }
}

struct PhotosPicOptions: View {

    @AppStorage(photosPicViewStyleKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var picStyle: ViewStyle = .grid
    @AppStorage(photosPicSortKey,
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate"))
    var picSort: PhotosPicSortType = .dateCreatedDescending

    var body: some View {
        PicViewStylePicker(selection: $picStyle)
        PhotosPicSortPicker(selection: $picSort)
    }
}

struct PhotosPicsSectionHeader: View {

    var count: Int
    var onFindDuplicates: (() -> Void)?

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"), count: count)
            } else {
                SectionHeader(title: String(localized: "Albums.Pics", table: "Albums"), count: count) {
                    if let onFindDuplicates {
                        Button(String(localized: "Duplicates.FindDuplicates", table: "Photos"),
                               systemImage: "photo.stack") {
                            onFindDuplicates()
                        }
                        Divider()
                    }
                    PhotosPicOptions()
                }
            }
        }
        .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 6.0, trailing: 20.0))
    }
}
