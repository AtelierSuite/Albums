import Engine
import SwiftUI

extension PicViewer {

    var displayedOrientationEdit: PicOrientationEdit {
        viewer.orientationEdit(for: viewer.displayedPicID)
    }

    var isEditingOrientation: Bool {
        viewer.orientationEdits[viewer.displayedPicID] != nil
    }

    @ViewBuilder
    var shareButton: some View {
        if viewer.displayedPic?.isVideo == true {
            if let videoURL = viewer.displayedVideoURL {
                ShareLink(
                    "Shared.Share",
                    item: videoURL,
                    preview: SharePreview(displayedPicName)
                )
            } else {
                Button("Shared.Share", systemImage: "square.and.arrow.up") { }
                    .disabled(true)
            }
        } else {
            ShareLink(
                "Shared.Share",
                item: shareImage,
                preview: SharePreview(
                    displayedPicName,
                    image: shareImage
                )
            )
            .disabled(currentImage == nil || isEditingOrientation)
        }
    }

    var rotateButton: some View {
        Button("Shared.Rotate", systemImage: "rotate.left") {
            viewer.rotateDisplayedPic()
        }
        .disabled(!viewer.canEditDisplayedOrientation)
    }

    var flipButton: some View {
        Button("Shared.Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
            viewer.flipDisplayedPic()
        }
        .disabled(!viewer.canEditDisplayedOrientation)
    }

    var deleteButton: some View {
        Button("Shared.Delete", systemImage: "trash", role: .destructive) {
            isConfirmingDeletePic = true
        }
        .confirmationDialog("Shared.DeleteConfirmation.Pic", isPresented: $isConfirmingDeletePic,
                            titleVisibility: .visible) {
            Button("Shared.Delete", role: .destructive) {
                deleteDisplayedPic()
            }
            Button("Shared.Cancel", role: .cancel) { }
        }
    }
}
