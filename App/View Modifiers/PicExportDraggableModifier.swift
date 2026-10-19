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
            content.draggable(PicVideoExportable(id: pic.id, name: pic.name))
        } else {
            content.draggable(PicImageExportable(id: pic.id, name: pic.name))
        }
    }
}
