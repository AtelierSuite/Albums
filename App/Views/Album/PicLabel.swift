import Engine
import SwiftUI

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func thumbnail(for pic: Pic) async -> UIImage? {
        let picID = pic.id
        if let cached = image(forKey: picID) {
            return cached
        }
        guard let prepared = await Self.loadThumbnail(picID: picID, data: pic.thumbnailData) else { return nil }
        setImage(prepared, forKey: picID)
        return prepared
    }

    @concurrent
    nonisolated private static func loadThumbnail(picID: String, data: Data?) async -> UIImage? {
        var data = data
        if data == nil {
            data = await DataActor.shared.thumbnailData(forPicWithID: picID)
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay()
    }
}

struct PicLabel: View {

    var pic: Pic
    var maintainsAspectRatio: Bool = false
    var showsPinBadge: Bool = false
    var usesCompactBadges: Bool = false
    var onAspectRatio: ((CGFloat) -> Void)?

    @State var isThumbnailReadyToPresent: Bool
    @State var thumbnail: Image?
    @State var fadesInThumbnail: Bool

    init(pic: Pic, maintainsAspectRatio: Bool = false, showsPinBadge: Bool = false,
         usesCompactBadges: Bool = false, onAspectRatio: ((CGFloat) -> Void)? = nil) {
        self.pic = pic
        self.maintainsAspectRatio = maintainsAspectRatio
        self.showsPinBadge = showsPinBadge
        self.usesCompactBadges = usesCompactBadges
        self.onAspectRatio = onAspectRatio
        let cached = ThumbnailCache.shared.image(forKey: pic.id)
        _isThumbnailReadyToPresent = State(initialValue: cached != nil)
        _thumbnail = State(initialValue: cached.map { Image(uiImage: $0) })
        _fadesInThumbnail = State(initialValue: cached == nil)
    }

    var body: some View {
        base
            .clipped()
            .contentShape(.rect)
            .clipShape(.rect(cornerRadius: 4.0))
            .task(id: pic.id) {
                let picID = pic.id
                if let cached = ThumbnailCache.shared.image(forKey: picID) {
                    reportAspectRatio(for: cached)
                    if thumbnail == nil {
                        thumbnail = Image(uiImage: cached)
                        isThumbnailReadyToPresent = true
                    }
                    return
                }
                let prepared = await ThumbnailCache.shared.thumbnail(for: pic)
                guard !Task.isCancelled else { return }
                if let prepared {
                    reportAspectRatio(for: prepared)
                    thumbnail = Image(uiImage: prepared)
                }
                isThumbnailReadyToPresent = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .picThumbnailDidChange)) { notification in
                guard notification.object as? String == pic.id,
                      let cached = ThumbnailCache.shared.image(forKey: pic.id) else { return }
                reportAspectRatio(for: cached)
                thumbnail = Image(uiImage: cached)
                isThumbnailReadyToPresent = true
            }
    }

    @ViewBuilder
    private var base: some View {
        if maintainsAspectRatio {
            rectangle
        } else {
            rectangle
                .aspectRatio(1.0, contentMode: .fit)
        }
    }

    private var rectangle: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .overlay(alignment: .top) {
                if isThumbnailReadyToPresent, let thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFill()
                        .transition(fadesInThumbnail ? .opacity.animation(.smooth.speed(2.0)) : .identity)
                }
            }
            .overlay {
                if isThumbnailReadyToPresent, thumbnail == nil {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.0, height: 24.0)
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.multicolor)
                        .transition(.opacity.animation(.smooth.speed(2.0)))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if pic.isVideo, let duration = pic.duration {
                    Text(formatDuration(duration))
                        .font(usesCompactBadges ? .system(size: 7.0) : .caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, usesCompactBadges ? 3.0 : 6.0)
                        .padding(.vertical, usesCompactBadges ? 1.0 : 2.0)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(usesCompactBadges ? 2.0 : 4.0)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsPinBadge {
                    Image(systemName: "pin.fill")
                        .font(.system(size: usesCompactBadges ? 7.0 : 10.0, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: usesCompactBadges ? 14.0 : 22.0,
                               height: usesCompactBadges ? 14.0 : 22.0,
                               alignment: .center)
                        .glassEffect(.regular.tint(.accentColor), in: .circle)
                        .padding(usesCompactBadges ? 2.0 : 4.0)
                        .accessibilityLabel(Text("Shared.Pinned"))
                }
            }
    }

    private func reportAspectRatio(for image: UIImage) {
        guard maintainsAspectRatio, image.size.height > 0.0 else { return }
        onAspectRatio?(image.size.width / image.size.height)
    }
}
