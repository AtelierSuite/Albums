import Engine
import SwiftUI

struct AlbumViewOptions {
    var albumStyle: Binding<AlbumViewStyle>
    var albumSort: Binding<SortType>
    var picSort: Binding<PicSortType>
    var picStyle: Binding<ViewStyle>
    var hideSectionHeaders: Binding<Bool>
}
