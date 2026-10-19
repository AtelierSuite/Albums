import Engine
import SwiftUI

struct AlbumNavigationStack: View {

    var album: Album
    @State var viewPath: [ViewPath] = []

    @Namespace var picTransitionNamespace

    @State var viewerManager = ViewerManager()

    var body: some View {
        ZStack {
            NavigationStack(path: $viewPath) {
                AlbumView(currentAlbum: album)
                    .navigationDestination(for: ViewPath.self) { viewPath in
                        switch viewPath {
                        case .album(let album):
                            AlbumView(currentAlbum: album)
                        case .picViewer(let namespace):
                            if let displayedPic = viewerManager.displayedPic {
                                if #available(iOS 18, *) {
                                    PicViewer(pic: displayedPic)
                                        .navigationTransition(.zoom(
                                            sourceID: viewerManager.displayedPicID,
                                            in: namespace))
                                } else {
                                    PicViewer(pic: displayedPic)
                                }
                            }
                        case .picViewerRestore:
                            if let displayedPic = viewerManager.displayedPic {
                                PicViewer(pic: displayedPic)
                            }
                        default: Color.clear
                        }
                    }
            }
        }
        .id(album.id)
    }
}
