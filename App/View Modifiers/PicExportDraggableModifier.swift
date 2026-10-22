import Engine
import SwiftUI

struct PicExportDraggableModifier: ViewModifier {

    let pic: Pic
    var isSelecting: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelecting {
            content
        } else if pic.isVideo {
            content.draggable(PicVideoExportable(id: pic.id, name: pic.name)) {
                PicDragPreview(picID: pic.id)
            }
        } else {
            content.draggable(PicImageExportable(id: pic.id, name: pic.name)) {
                PicDragPreview(picID: pic.id)
            }
        }
    }
}

struct PicDragPreview: View {

    let picID: String

    var body: some View {
        if let image = ThumbnailCache.shared.image(forKey: picID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 120.0, maxHeight: 120.0)
                .clipShape(.rect(cornerRadius: 4.0))
        }
    }
}
