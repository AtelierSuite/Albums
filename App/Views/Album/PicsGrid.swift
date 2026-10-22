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

    @State private var gridWidth: CGFloat = 0.0
    @State private var anchorIndex: Int?
    @State private var paintSelected: Bool = false
    @State private var paintedRange: ClosedRange<Int>?
    @State private var originalSelected: [Int: Bool] = [:]
    @State private var aspectRatios: [String: CGFloat] = [:]
    @State private var masonryPinch: MasonryPinchAnchor?

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
                                  onBegan: { location, _ in beginMasonryPinch(at: location) },
                                  onChanged: { scale, _, scroller in updateMasonryPinch(scale: scale, scroller: scroller) },
                                  onEnded: { _, _ in masonryPinch = nil }))
        .gesture(SelectionPanGesture(isEnabled: isSelecting && style != .masonry,
                                     coordinateSpace: Self.selectionSpace,
                                     onChange: { updateSelection(at: $0) },
                                     onEnd: { resetSelectionDrag() }))
    }

    private var fittedColumnCount: Int {
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

    private func picCellBase(for pic: Pic, maintainsAspectRatio: Bool) -> some View {
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

    private func beginMasonryPinch(at location: CGPoint) {
        let layout = masonryLayout(columns: fittedColumnCount)
        let nearest = layout.frames.min { lhs, rhs in
            distance(from: location, to: lhs.value) < distance(from: location, to: rhs.value)
        }
        guard let nearest else { return }
        let frame = nearest.value
        masonryPinch = MasonryPinchAnchor(startCount: fittedColumnCount,
                                          currentCount: fittedColumnCount,
                                          range: GridColumnLimit.pics.range(width: gridWidth),
                                          entryID: nearest.key,
                                          fraction: min(max((location.y - frame.minY) / frame.height, 0.0), 1.0))
    }

    // SwiftUI doesn't refresh gesture representables mid-gesture, so columnCount is stale here.
    private func updateMasonryPinch(scale: CGFloat, scroller: PinchZoomScroller) {
        guard var pinch = masonryPinch else { return }
        let steps = Int((log(max(scale, 0.01)) / log(1.2)).rounded())
        let target = min(max(pinch.startCount - steps, min(pinch.range.lowerBound, pinch.startCount)),
                         max(pinch.range.upperBound, pinch.startCount))
        guard target != pinch.currentCount else { return }
        let oldLayout = masonryLayout(columns: pinch.currentCount)
        let newLayout = masonryLayout(columns: target)
        guard let oldFrame = oldLayout.frames[pinch.entryID],
              let newFrame = newLayout.frames[pinch.entryID] else { return }
        let delta = (newFrame.minY + pinch.fraction * newFrame.height)
            - (oldFrame.minY + pinch.fraction * oldFrame.height)
        let scrollDelta = scroller.clampedDelta(delta, contentHeightChange: newLayout.height - oldLayout.height)
        let animation = Animation.smooth(duration: 0.25)
        withAnimation(animation) {
            onColumnCountChange?(target)
        }
        pinch.currentCount = target
        masonryPinch = pinch
        scroller.layoutAndScroll(by: scrollDelta, animation: animation)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let horizontal = max(rect.minX - point.x, 0.0, point.x - rect.maxX)
        let vertical = max(rect.minY - point.y, 0.0, point.y - rect.maxY)
        return horizontal * horizontal + vertical * vertical
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

    var masonryColumns: [[MasonryEntry]] {
        masonryColumns(count: fittedColumnCount)
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

    func masonryLayout(columns count: Int) -> MasonryLayout {
        let columns = masonryColumns(count: count)
        let cellWidth = max((gridWidth - 2.0 * CGFloat(columns.count - 1)) / CGFloat(columns.count), 1.0)
        var frames: [String: CGRect] = [:]
        var height = 0.0
        for (index, column) in columns.enumerated() {
            var top = 0.0
            for entry in column {
                let cellHeight = cellWidth / max(entry.aspectRatio, 0.01)
                frames[entry.id] = CGRect(x: CGFloat(index) * (cellWidth + 2.0), y: top,
                                          width: cellWidth, height: cellHeight)
                top += cellHeight + 2.0
            }
            height = max(height, top - 2.0)
        }
        return MasonryLayout(frames: frames, height: height)
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

struct MasonryLayout {
    let frames: [String: CGRect]
    let height: CGFloat
}

struct MasonryPinchAnchor {
    let startCount: Int
    var currentCount: Int
    let range: ClosedRange<Int>
    let entryID: String
    let fraction: CGFloat
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
