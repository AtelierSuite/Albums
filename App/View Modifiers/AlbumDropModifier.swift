import Engine
import SwiftUI

struct AlbumDropModifier: ViewModifier {

    var onDrop: (([Drop], Album) -> Void)?
    var onDropFiles: (([URL], Album) -> Void)?
    var album: Album

    init(onDrop: (([Drop], Album) -> Void)? = nil,
         onDropFiles: (([URL], Album) -> Void)? = nil,
         album: Album) {
        self.onDrop = onDrop
        self.onDropFiles = onDropFiles
        self.album = album
    }

    func body(content: Content) -> some View {
        content
            .dropDestination(for: Drop.self) { items, _ in
                var fileURLs: [URL] = []
                var drops: [Drop] = []
                for item in items {
                    if let url = item.file {
                        fileURLs.append(url)
                    } else {
                        drops.append(item)
                    }
                }
                if !drops.isEmpty, let onDrop {
                    onDrop(drops, album)
                }
                if !fileURLs.isEmpty, let onDropFiles {
                    onDropFiles(fileURLs, album)
                }
                return true
            }
    }
}

extension View {
    func albumDropDestination(onDrop: (([Drop], Album) -> Void)? = nil,
                              onDropFiles: (([URL], Album) -> Void)? = nil,
                              album: Album) -> some View {
        modifier(AlbumDropModifier(onDrop: onDrop, onDropFiles: onDropFiles, album: album))
    }
}
