import Engine
import SwiftUI

extension PicViewer {

    var infoButton: some View {
        Button {
            isInfoPresented = true
        } label: {
            Label {
                Text("Info", tableName: "ContentCredentials")
            } icon: {
                Image(systemName: "info.circle")
            }
        }
    }

    @ViewBuilder
    var aiContentOverlay: some View {
        if let displayedAIContent {
            Button {
                isInfoPresented = true
            } label: {
                AIContentChip(kind: displayedAIContent)
            }
            .buttonStyle(.plain)
            .padding(8.0)
            .transition(.opacity)
        }
    }

    var displayedPixelSize: CGSize? {
        if viewer.displayedPic?.isVideo == true { return videoResolution }
        guard let image = viewer.displayedImage else { return nil }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}

struct PicInfoPresenter: ViewModifier {

    @Environment(ViewerManager.self) var viewer

    @Binding var isPresented: Bool
    @Binding var aiContent: AIContentKind?
    var pixelSize: CGSize?
    var albumName: String?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let displayedPic = viewer.displayedPic {
                    PicInfoSheet(pic: displayedPic, pixelSize: pixelSize, albumName: albumName)
                        .presentationDetents([.medium, .large])
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .picContentCredentialsDidChange)) { notification in
                guard let displayedPic = viewer.displayedPic,
                      notification.object as? String == displayedPic.id else { return }
                let kind = (notification.userInfo?["aiContent"] as? Int).flatMap(AIContentKind.init(rawValue:))
                displayedPic.aiContent = kind
                withAnimation(.smooth.speed(2.0)) {
                    aiContent = kind
                }
            }
    }
}
