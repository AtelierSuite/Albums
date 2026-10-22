import Engine
import SwiftUI

struct AlbumViewOptions {
    var albumStyle: Binding<AlbumViewStyle>
    var albumSort: Binding<SortType>
    var picSort: Binding<PicSortType>
    var picStyle: Binding<ViewStyle>
    var hideSectionHeaders: Binding<Bool>
}

struct AlbumViewOptionsKey: FocusedValueKey {
    typealias Value = AlbumViewOptions
}

extension FocusedValues {
    var albumViewOptions: AlbumViewOptions? {
        get { self[AlbumViewOptionsKey.self] }
        set { self[AlbumViewOptionsKey.self] = newValue }
    }
}

struct AlbumViewOptionsFocusModifier: ViewModifier {
    let options: AlbumViewOptions

    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content.focusedSceneValue(\.albumViewOptions, options)
#else
        content
#endif
    }
}
