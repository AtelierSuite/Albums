import Engine
import SwiftUI

struct PicsGrid<Content: View>: View {

    @Environment(\.colorScheme) var colorScheme

    var namespace: Namespace.ID

    var pics: [Pic]
    var placeholderCount: Int = 0
    @Binding var isSelecting: Bool
    @State var enableSelection: Bool = true
    var columnCount: Int = 4
    var style: ViewStyle = .grid
    var highlightedPicID: String?
    var isSelected: ((Pic) -> Bool)?
    var onSelect: (Pic) -> Void
    var selectedCount: () -> Int
    var onRename: ((Pic) -> Void)?
    var onTogglePin: ((Pic) -> Void)?
    var onDelete: ((Pic) -> Void)?
    @ViewBuilder var moveMenu: (Pic) -> Content

    private static var selectionSpace: String { "PicsGridSelectionSpace" }

    @State private var gridWidth: CGFloat = 0.0
    @State private var anchorIndex: Int?
    @State private var paintSelected: Bool = false
    @State private var paintedRange: ClosedRange<Int>?
    @State private var originalSelected: [Int: Bool] = [:]
    @State private var aspectRatios: [String: CGFloat] = [:]

    var body: some View {
        Group {
            if style == .masonry {
                masonryGrid
            } else {
                squareGrid
            }
        }
        .coordinateSpace(.named(Self.selectionSpace))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            gridWidth = width
        }
        .gesture(SelectionPanGesture(isEnabled: isSelecting && style != .masonry,
                                     coordinateSpace: Self.selectionSpace,
                                     onChange: { updateSelection(at: $0) },
                                     onEnd: { resetSelectionDrag() }))
        .animation(.smooth.speed(2.0), value: columnCount)
    }

    private var squareGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: columnCount),
                  spacing: 2.0) {
            ForEach(pics) { pic in
                picCell(for: pic, maintainsAspectRatio: false)
            }
            if placeholderCount > 0 {
                let visiblePlaceholders = min(placeholderCount, columnCount * 10)
                ForEach(0..<visiblePlaceholders, id: \.self) { _ in
                    placeholderCell
                }
            }
        }
    }

    private var masonryGrid: some View {
        HStack(alignment: .top, spacing: 2.0) {
            ForEach(Array(masonryColumns.enumerated()), id: \.offset) { column in
                LazyVStack(spacing: 2.0) {
                    ForEach(column.element) { entry in
                        if let pic = entry.pic {
                            picCell(for: pic, maintainsAspectRatio: true)
                                .aspectRatio(entry.aspectRatio, contentMode: .fit)
                        } else {
                            placeholderCell
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var placeholderCell: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 4.0))
    }

    private var masonryColumns: [[MasonryEntry]] {
        let count = max(columnCount, 1)
        var columns = Array(repeating: [MasonryEntry](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        func place(_ entry: MasonryEntry) {
            var target = 0
            for index in 1..<count where heights[index] < heights[target] {
                target = index
            }
            columns[target].append(entry)
            heights[target] += 1.0 / max(entry.aspectRatio, 0.01)
        }
        for pic in pics {
            place(MasonryEntry(id: pic.id, pic: pic, aspectRatio: aspectRatios[pic.id] ?? 1.0))
        }
        if placeholderCount > 0 {
            let visiblePlaceholders = min(placeholderCount, count * 10)
            for index in 0..<visiblePlaceholders {
                place(MasonryEntry(id: "placeholder-\(index)", pic: nil, aspectRatio: 1.0))
            }
        }
        return columns
    }

    @ViewBuilder
    private func picCell(for pic: Pic, maintainsAspectRatio: Bool) -> some View {
        PicLabel(pic: pic,
                 maintainsAspectRatio: maintainsAspectRatio,
                 showsPinBadge: onTogglePin != nil && pic.isPinned,
                 usesCompactBadges: usesCompactBadges,
                 onAspectRatio: maintainsAspectRatio ? { ratio in
                     if aspectRatios[pic.id] != ratio {
                         aspectRatios[pic.id] = ratio
                     }
                 } : nil)
            .overlay {
                if highlightedPicID == pic.id {
                    RoundedRectangle(cornerRadius: 4.0)
                        .strokeBorder(.tint, lineWidth: 3.0)
                        .transition(.opacity)
                }
            }
            .overlay {
                if isSelecting {
                    if let isSelected {
                        ZStack(alignment: .bottomTrailing) {
                            SelectionOverlay(isSelected(pic))
                            Color.clear
                        }
                        .transition(.opacity.animation(.smooth.speed(2.0)))
                    }
                }
            }
            .contentShape(.rect)
            .accessibilityIdentifier("pic:\(pic.name)")
            .onTapGesture {
                onSelect(pic)
            }
            .modifier(PicExportDraggableModifier(pic: pic, isSelecting: isSelecting))
            .matchedTransitionSource(id: pic.id, in: namespace)
            .contextMenu {
                if !isSelecting {
                    if enableSelection {
                        Button("Shared.Select", systemImage: "checkmark.circle") {
                            doWithAnimation {
                                isSelecting = true
                                onSelect(pic)
                            }
                        }
                        Divider()
                    }
                    Button("Shared.Copy", systemImage: "doc.on.doc") {
                        Task {
                            if let data = await DataActor.shared.imageData(forPicWithID: pic.id),
                               let image = UIImage(data: data) {
                                UIPasteboard.general.image = image
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                CopiedToast.showCopied()
                            }
                        }
                    }
                    ShareLink(item: PicShareable(picID: pic.id),
                              preview: SharePreview(pic.name,
                                                    image: PicShareable(picID: pic.id))) {
                        Label("Shared.Share", systemImage: "square.and.arrow.up")
                    }
                    pinMenuItem(for: pic)
                    if let onRename {
                        Divider()
                        Button("Shared.Rename", systemImage: "pencil") {
                            onRename(pic)
                        }
                    }
                    Divider()
                    if let albumID = pic.containingAlbumID {
                        Button("Shared.SetAsCover", systemImage: "photo") {
                            Task {
                                await DataActor.shared.setAsAlbumCover(for: pic.id)
                                AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
                            }
                        }
                    }
                    Divider()
                    moveMenu(pic)
                    if let onDelete {
                        Divider()
                        Button("Shared.Delete", systemImage: "trash", role: .destructive) {
                            onDelete(pic)
                        }
                    }
                }
            } preview: {
                PicPreview(picID: pic.id)
            }
#if targetEnvironment(macCatalyst)
            .hoverEffect(.highlight)
#endif
    }

    private func resetSelectionDrag() {
        anchorIndex = nil
        paintedRange = nil
        originalSelected.removeAll()
    }

    private func picIndex(at location: CGPoint) -> Int? {
        guard gridWidth > 0.0, columnCount > 0,
              location.x >= 0.0, location.y >= 0.0 else {
            return nil
        }
        let spacing = 2.0
        let itemWidth = (gridWidth - spacing * Double(columnCount - 1)) / Double(columnCount)
        guard itemWidth > 0.0 else { return nil }
        let pitch = itemWidth + spacing
        let column = Int(location.x / pitch)
        let row = Int(location.y / pitch)
        guard column >= 0, column < columnCount else { return nil }
        let index = row * columnCount + column
        guard index >= 0, index < pics.count else { return nil }
        return index
    }

    private func setSelected(_ index: Int, _ selected: Bool) {
        let pic = pics[index]
        if (isSelected?(pic) ?? false) != selected {
            onSelect(pic)
        }
    }

    private func updateSelection(at location: CGPoint) {
        guard let current = picIndex(at: location) else { return }
        guard let anchor = anchorIndex else {
            let original = isSelected?(pics[current]) ?? false
            originalSelected[current] = original
            paintSelected = !original
            anchorIndex = current
            paintedRange = current...current
            setSelected(current, paintSelected)
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        let newRange = min(anchor, current)...max(anchor, current)
        if newRange == paintedRange { return }
        if let old = paintedRange {
            for index in old where !newRange.contains(index) {
                setSelected(index, originalSelected[index] ?? false)
            }
        }
        for index in newRange where !(paintedRange?.contains(index) ?? false) {
            if originalSelected[index] == nil {
                originalSelected[index] = isSelected?(pics[index]) ?? false
            }
            setSelected(index, paintSelected)
        }
        paintedRange = newRange
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension PicsGrid {
    var usesCompactBadges: Bool {
        guard gridWidth > 0.0, columnCount > 0 else { return false }
        let itemWidth = (gridWidth - 2.0 * Double(columnCount - 1)) / Double(columnCount)
        return itemWidth < 60.0
    }

    @ViewBuilder
    func pinMenuItem(for pic: Pic) -> some View {
        if let onTogglePin {
            Divider()
            PinButton(isPinned: pic.isPinned) {
                onTogglePin(pic)
            }
        }
    }
}

struct MasonryEntry: Identifiable {
    let id: String
    let pic: Pic?
    let aspectRatio: CGFloat
}

struct PicShareable: Transferable {
    let picID: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { shareable in
            if let data = await DataActor.shared.imageData(forPicWithID: shareable.picID),
               let image = UIImage(data: data),
               let pngData = image.pngData() {
                return pngData
            }
            return Data()
        }
    }
}

struct PicPreview: View {
    let picID: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(.primary.opacity(0.05))
                    .frame(width: 200, height: 200)
            }
        }
        .task {
            if let thumbData = await DataActor.shared.thumbnailData(forPicWithID: picID),
               let uiImage = UIImage(data: thumbData) {
                image = uiImage
            }
        }
    }
}
