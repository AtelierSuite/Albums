import Engine

extension AlbumView {

    var preferencesAlbumID: String {
        currentAlbum?.id ?? "__root__"
    }

    func loadPreferences() async {
        let prefs = await DataActor.shared.preferences(forAlbumWithID: preferencesAlbumID)
        albumSort = SortType(rawValue: prefs.albumSort) ?? .nameAscending
        albumStyle = ViewStyle(rawValue: prefs.albumViewStyle) ?? .grid
        albumColumnCount = prefs.albumColumnCount
        picSortType = PicSortType(rawValue: prefs.picSort) ?? .dateAddedDescending
        columnCount = prefs.picColumnCount
        hideSectionHeaders = prefs.hideSectionHeaders
        albumSortState = albumSort
        albumStyleState = albumStyle
    }

    func savePreference() {
        let prefs = AlbumPreferences(
            albumID: preferencesAlbumID,
            albumSort: albumSort.rawValue,
            albumViewStyle: albumStyle.rawValue,
            albumColumnCount: albumColumnCount,
            picSort: picSortType.rawValue,
            picColumnCount: columnCount,
            hideSectionHeaders: hideSectionHeaders
        )
        let dataActor = DataActor.shared
        Task {
            await dataActor.savePreferences(prefs)
            SyncManager.shared.schedulePush(forLibrary: dataActor.collectionID)
        }
    }
}
