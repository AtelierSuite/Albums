import Engine
import SwiftUI
import TipKit

extension AlbumView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if isSelectingPics {
#if targetEnvironment(macCatalyst)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    startOrStopSelectingPics()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItemGroup(placement: .topBarTrailing) {
                selectedPicsActionsMenu
                Text("Shared.Selected.\(selectedPics.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize()
                Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                    deletePics()
                }
                .disabled(selectedPics.isEmpty)
                .tint(.red)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    selectOrDeselectAllPics()
                } label: {
                    if pics.count == selectedPics.count {
                        Label("Shared.DeselectAll", image: "checkmark.circle.slash")
                    } else {
                        Label("Shared.SelectAll", systemImage: "checkmark.circle")
                    }
                }
            }
#else
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    startOrStopSelectingPics()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                selectedPicsActionsMenu
                Text("Shared.Selected.\(selectedPics.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize()
                Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                    deletePics()
                }
                .disabled(selectedPics.isEmpty)
                .tint(.red)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    selectOrDeselectAllPics()
                } label: {
                    if pics.count == selectedPics.count {
                        Label("Shared.DeselectAll", image: "checkmark.circle.slash")
                    } else {
                        Label("Shared.SelectAll", systemImage: "checkmark.circle")
                    }
                }
            }
#endif
        } else {
            if UIDevice.current.userInterfaceIdiom != .phone {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Shared.Select") {
                        startOrStopSelectingPics()
                    }
                    .disabled(pics.isEmpty)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
#if targetEnvironment(macCatalyst)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(String(localized: "Duplicates.FindDuplicates", table: "Photos"),
                       systemImage: "photo.stack") {
                    isDuplicateCheckerPresented = true
                }
                .accessibilityIdentifier("findDuplicates")
                Button(String(localized: "Sort.SortIntelligently", table: "Photos"),
                       systemImage: "wand.and.stars") {
                    isIntelligentSortPresented = true
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
#endif
            ToolbarItemGroup(placement: .topBarTrailing) {
                importMenu
                    .popoverTip(ImportTip(), arrowEdge: .top) { _ in
                        NewAlbumTip.hasSeenImportTip = true
                    }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Shared.Create", systemImage: "rectangle.stack.badge.plus") {
                    isAddingAlbum = true
                }
                .popoverTip(NewAlbumTip(), arrowEdge: .top) { _ in
                    LibrariesTip.hasSeenNewAlbumTip = true
                }
            }
            if UIDevice.current.userInterfaceIdiom == .phone {
                ToolbarItemGroup(placement: .bottomBar) {
                    filterMenu
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Shared.Select") {
                        startOrStopSelectingPics()
                    }
                    .disabled(pics.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    var selectedPicsActionsMenu: some View {
        Menu("Shared.More", systemImage: "ellipsis") {
            PicMoveMenu(title: "Shared.Move", systemImage: "tray.full",
                        pics: selectedPics, containingAlbum: currentAlbum,
                        totalAlbumCount: totalAlbumCount) {
                refreshDataAfterPicMoved()
            } onOtherLibraries: {
                movePayload = .pics(selectedPics)
            }
            PinButton(isPinned: selectedPics.allSatisfy(\.isPinned)) {
                togglePin(for: selectedPics)
            }
        }
        .disabled(selectedPics.isEmpty)
    }

    @ViewBuilder
    var filterMenu: some View {
        Menu {
            Button(String(localized: "Duplicates.FindDuplicates", table: "Photos"),
                   systemImage: "photo.stack") {
                isDuplicateCheckerPresented = true
            }
            .accessibilityIdentifier("findDuplicates")
            Button(String(localized: "Sort.SortIntelligently", table: "Photos"),
                   systemImage: "wand.and.stars") {
                isIntelligentSortPresented = true
            }
            Section(String(localized: "Albums.Albums", table: "Albums")) {
                AlbumViewStylePicker(selection: $albumStyleState)
                Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $albumSortState) {
                    Text("Shared.Sort.Name.Ascending")
                        .tag(SortType.nameAscending)
                    Text("Shared.Sort.Name.Descending")
                        .tag(SortType.nameDescending)
                    Text("Shared.Sort.PicCount.Ascending")
                        .tag(SortType.sizeAscending)
                    Text("Shared.Sort.PicCount.Descending")
                        .tag(SortType.sizeDescending)
                }
                .pickerStyle(.menu)
            }
            Section(String(localized: "Albums.Pics", table: "Albums")) {
                Picker(String(localized: "Albums.Style", table: "Albums"),
                       systemImage: "paintbrush",
                       selection: $picViewStyle.animation(.smooth.speed(2.0))) {
                    Label(String(localized: "Albums.Style.Grid", table: "Albums"),
                          systemImage: "square.grid.2x2")
                        .tag(ViewStyle.grid)
                    Label(String(localized: "Albums.Style.Masonry", table: "Albums"),
                          systemImage: "rectangle.3.offgrid")
                        .tag(ViewStyle.masonry)
                }
                .pickerStyle(.menu)
                GridSizePicker(selection: $columnCount, sizes: [2, 3, 4, 5, 8], kind: .pics)
                Picker("Shared.Sort", systemImage: "arrow.up.arrow.down", selection: $picSortType) {
                    Text("Shared.Sort.DateAdded.Ascending")
                        .tag(PicSortType.dateAddedAscending)
                    Text("Shared.Sort.DateAdded.Descending")
                        .tag(PicSortType.dateAddedDescending)
                    Text("Shared.Sort.Name.Ascending")
                        .tag(PicSortType.nameAscending)
                    Text("Shared.Sort.Name.Descending")
                        .tag(PicSortType.nameDescending)
                    Text("Shared.Sort.ProminentColor")
                        .tag(PicSortType.prominentColor)
                }
                .pickerStyle(.menu)
            }
            Section {
                Toggle(String(localized: "Albums.HideHeaders", table: "Albums"),
                       isOn: $hideSectionHeaders)
            }
        } label: {
            Label("Shared.Filter", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityIdentifier("filterMenu")
        .menuActionDismissBehavior(.disabled)
        .menuOrder(.fixed)
    }

    @ViewBuilder
    var importMenu: some View {
        Menu("Shared.Import", systemImage: "square.and.arrow.down.on.square") {
            Section(String(localized: "Import.Section.FromPhotosApp", table: "Import")) {
                Button {
                    isPhotosPickerPresented = true
                } label: {
                    Label(String(localized: "Import.SelectPhotos", table: "Import"),
                          systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    isVideosPickerPresented = true
                } label: {
                    Label(String(localized: "Import.SelectVideos", table: "Import"),
                          systemImage: "video")
                }
                Button {
                    isBrowsingAlbums = true
                } label: {
                    Label(String(localized: "Import.BrowseAlbums", table: "Import"),
                          systemImage: "rectangle.stack")
                }
                Button {
                    isBrowsingFolders = true
                } label: {
                    Label(String(localized: "Import.SelectFolder", table: "Import"),
                          systemImage: "folder")
                }
            }
            Section(String(localized: "Import.Section.FromFilesApp", table: "Import")) {
                Button {
                    presentFileImporter()
                } label: {
                    Label(String(localized: "Import.SelectFromFiles", table: "Import"),
                          systemImage: "document")
                }
            }
        }
    }
}
