import Photos
import SwiftUI

struct CollectionView: View {

    @EnvironmentObject var navigation: NavigationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(ViewerManager.self) var viewer
    @Environment(PhotosViewerManager.self) var photosViewer
    @State var hasRestoredPath: Bool = false

    @AppStorage("PhotosModeEnabled",
                store: UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")) var isPhotosModeEnabled: Bool = false

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        if isPhone {
            Group {
                if hasRestoredPath {
                    navigationStack
                } else {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()
                }
            }
            .task(id: libraryManager.hasLoadedLibraries) {
                guard libraryManager.hasLoadedLibraries, !hasRestoredPath else { return }
                navigation.collectionTabPath = await navigation.restoredLibraryPath(
                    currentLibraryID: libraryManager.currentLibrary.id,
                    isPhotosModeEnabled: isPhotosModeEnabled
                )
                hasRestoredPath = true
            }
            .onChange(of: navigation.collectionTabPath) { _, _ in
                guard hasRestoredPath else { return }
                navigation.saveLibraryLocation()
            }
            .onChange(of: libraryManager.currentLibrary.id) { _, newID in
                guard case .library(let openID) = navigation.collectionTabPath.first,
                      openID != newID else { return }
                navigation.collectionTabPath = [.library(id: newID)]
            }
            .onChange(of: isPhotosModeEnabled) { _, isEnabled in
                if !isEnabled, navigation.collectionTabPath.first == .photosLibrary {
                    navigation.collectionTabPath.removeAll()
                }
            }
        } else {
            navigationStack
                .onChange(of: isPhotosModeEnabled) { _, _ in
                    navigation.collectionTabPath.removeAll()
                }
        }
    }

    var navigationStack: some View {
        NavigationStack(path: $navigation.collectionTabPath) {
            Group {
                if isPhone {
                    LibrariesView()
                } else if isPhotosModeEnabled {
                    PhotosCollectionView()
                } else {
                    AlbumView()
                }
            }
            .navigationDestination(for: ViewPath.self, destination: { viewPath in
              switch viewPath {
              case .library:
                  AlbumView()
                      .id(libraryManager.currentLibrary.id)
              case .photosLibrary:
                  PhotosCollectionView()
              case .album(let album):
                  AlbumView(currentAlbum: album)
              case .picViewer(let namespace):
                  if let displayedPic = viewer.displayedPic {
                      if #available(iOS 18, *) {
                          PicViewer(pic: displayedPic)
                          .navigationTransition(.zoom(sourceID: viewer.displayedPicID,
                                                      in: namespace))
                      } else {
                          PicViewer(pic: displayedPic)
                      }
                  }
              case .photosFolder(let wrapper):
                  PhotosFolderView(folder: wrapper.collectionList)
              case .photosAlbum(let wrapper):
                  PhotosAlbumContentView(collection: wrapper.collection)
              case .photosAssetViewer(let wrapper, let namespace):
                  if #available(iOS 18, *) {
                      PhotosAssetViewer(asset: wrapper.asset)
                          .navigationTransition(.zoom(
                              sourceID: wrapper.asset.localIdentifier,
                              in: namespace))
                  } else {
                      PhotosAssetViewer(asset: wrapper.asset)
                  }
              case .picViewerRestore:
                  if let displayedPic = viewer.displayedPic {
                      PicViewer(pic: displayedPic)
                  }
              case .photosAssetViewerRestore:
                  if let displayedAsset = photosViewer.displayedAsset {
                      PhotosAssetViewer(asset: displayedAsset)
                  }
              default: Color.clear
              }
            })
        }
    }
}
