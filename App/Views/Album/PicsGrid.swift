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
    var onColumnCountChange: ((Int) -> Void)?
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

    @State var gridWidth: CGFloat = 0.0
    @State private var anchorIndex: Int?
    @State private var paintSelected: Bool = false
    @State private var paintedRange: ClosedRange<Int>?
    @State private var originalSelected: [Int: Bool] = [:]
    @State private var aspectRatios: [String: CGFloat] = [:]
    @State var masonryPinch: MasonryPinchAnchor?
    @State var masonryVisibleRange: ClosedRange<CGFloat>?

    var body: some View {
        Group {
            if style == .masonry {
                masonryGrid
            } else {
                PinchZoomGrid(columnCount: fittedColumnCount,
                              itemCount: pics.count + min(placeholderCount, fittedColumnCount * 10),
                              range: GridColumnLimit.pics.range(width: gridWidth),
                              cropsToTop: true,
                              onColumnCountChange: onColumnCountChange,
                              cachedImage: cachedThumbnail(at:),
                              loadImage: loadThumbnail(at:)) {
                    squareGrid
                }
            }
        }
        .coordinateSpace(.named(Self.selectionSpace))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            gridWidth = width
        }
        .gesture(PinchZoomGesture(isEnabled: style == .masonry && onColumnCountChange != nil,
                                  coordinateSpace: Self.selectionSpace,
                                  onBegan: { location, viewport, _ in
                                      beginMasonryPinch(at: location, viewport: viewport)
                                  },
                                  onChanged: { scale, _, scroller in
                                      updateMasonryPinch(scale: scale, scroller: scroller)
                                  },
                                  onEnded: { _, scroller in endMasonryPinch(scroller: scroller) }))
        .gesture(SelectionPanGesture(isEnabled: isSelecting && style != .masonry,
                                     coordinateSpace: Self.selectionSpace,
                                     onChange: { updateSelection(at: $0) },
                                     onEnd: { resetSelectionDrag() }))
    }

    var fittedColumnCount: Int {
        GridColumnLimit.pics.columns(columnCount, width: gridWidth)
    }

    private var squareGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.0), count: fittedColumnCount),
                  spacing: 2.0) {
            ForEach(pics) { pic in
                picCell(for: pic, maintainsAspectRatio: false)
            }
            if placeholderCount > 0 {
                let visiblePlaceholders = min(placeholderCount, fittedColumnCount * 10)
                ForEach(0..<visiblePlaceholders, id: \.self) { _ in
                    placeholderCell
                }
            }
        }
    }

    private var masonryGrid: some View {
        let layout = masonryLayout(columns: fittedColumnCount)
        return ZStack(alignment: .topLeading) {
            ForEach(layout.entries(in: masonryVisibleRange, including: highlightedPicID)) { entry in
                if let frame = layout.frames[entry.id] {
                    Group {
                        if let pic = entry.pic {
                            picCell(for: pic, maintainsAspectRatio: true)
                        } else {
                            placeholderCell
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout.height, maxHeight: layout.height, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.bounds(of: .scrollView) ?? .infinite
        } action: { visible in
            updateMasonryVisibleRange(visible)
        }
        .opacity(masonryPinch == nil ? 1.0 : 0.0)
        .overlay(alignment: .topLeading) {
            if let masonryPinch {
                masonryMorphLayer(for: masonryPinch)
            }
        }
    }

    @ViewBuilder
    private func picCell(for pic: Pic, maintainsAspectRatio: Bool) -> some View {
        picCellBase(for: pic, maintainsAspectRatio: maintainsAspectRatio)
            .modifier(DeferredOverlayModifier {
                Color.clear
                    .contentShape(.rect)
                    .modifier(PicExportDraggableModifier(pic: pic, isSelecting: isSelecting))
                    .contextMenu {
                        picContextMenu(for: pic)
                    } preview: {
                        PicPreview(picID: pic.id)
                    }
            })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("pic:\(pic.name)")
            .onTapGesture {
                onSelect(pic)
            }
            .modifier(PicTransitionSourceModifier(picID: pic.id, namespace: namespace))
#if targetEnvironment(macCatalyst)
            .hoverEffect(.highlight)
#endif
    }

    func picCellBase(for pic: Pic, maintainsAspectRatio: Bool) -> some View {
        PicLabel(pic: pic,
                 maintainsAspectRatio: maintainsAspectRatio,
                 showsPinBadge: onTogglePin != nil && pic.isPinned,
                 usesCompactBadges: usesCompactBadges(columns: fittedColumnCount),
                 onAspectRatio: maintainsAspectRatio ? { ratio in
                     if abs(aspectRatio(for: pic) - ratio) > 0.001 {
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
    }

    @ViewBuilder
    private func picContextMenu(for pic: Pic) -> some View {
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
    }

    private func resetSelectionDrag() {
        anchorIndex = nil
        paintedRange = nil
        originalSelected.removeAll()
    }

    private func picIndex(at location: CGPoint) -> Int? {
        guard gridWidth > 0.0, fittedColumnCount > 0,
              location.x >= 0.0, location.y >= 0.0 else {
            return nil
        }
        let spacing = 2.0
        let itemWidth = (gridWidth - spacing * Double(fittedColumnCount - 1)) / Double(fittedColumnCount)
        guard itemWidth > 0.0 else { return nil }
        let pitch = itemWidth + spacing
        let column = Int(location.x / pitch)
        let row = Int(location.y / pitch)
        guard column >= 0, column < fittedColumnCount else { return nil }
        let index = row * fittedColumnCount + column
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
    var placeholderCell: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 4.0))
    }

    func masonryColumns(count requestedCount: Int) -> [[MasonryEntry]] {
        let count = max(requestedCount, 1)
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
            place(MasonryEntry(id: pic.id, pic: pic, aspectRatio: aspectRatio(for: pic)))
        }
        if placeholderCount > 0 {
            let visiblePlaceholders = min(placeholderCount, count * 10)
            for index in 0..<visiblePlaceholders {
                place(MasonryEntry(id: "placeholder-\(index)", pic: nil, aspectRatio: 1.0))
            }
        }
        return columns
    }

    func cachedThumbnail(at index: Int) -> UIImage? {
        guard index < pics.count else { return nil }
        return ThumbnailCache.shared.image(forKey: pics[index].id)
    }

    func loadThumbnail(at index: Int) async -> UIImage? {
        guard index < pics.count else { return nil }
        return await ThumbnailCache.shared.thumbnail(for: pics[index])
    }

    func aspectRatio(for pic: Pic) -> CGFloat {
        aspectRatios[pic.id] ?? pic.thumbnailAspectRatio ?? 1.0
    }

    func usesCompactBadges(columns: Int) -> Bool {
        guard gridWidth > 0.0, columns > 0 else { return false }
        let itemWidth = (gridWidth - 2.0 * Double(columns - 1)) / Double(columns)
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
