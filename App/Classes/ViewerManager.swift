import AVFoundation
import Engine
import Foundation
import StoreKit
import SwiftUI

@MainActor @Observable
class ViewerManager {

    static let picOpenCountKey = "PicOpenCount"

    var displayedPicID: String = ""
    var displayedPic: Pic?
    var displayedThumbnail: UIImage?
    var displayedImage: UIImage?
    var isFullImageLoaded: Bool = false
    var downloadingOriginalPicID: String?
    var downloadProgress: Double?
    var failedDownloadPicID: String?
    var displayedVideoURL: URL?
    var videoPlayer: AVPlayer?

    var allPics: [Pic] = []
    var currentIndex: Int = 0

    var hasNext: Bool { currentIndex < allPics.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 }

    var isDownloadingDisplayedOriginal: Bool {
        downloadingOriginalPicID != nil && downloadingOriginalPicID == displayedPicID
    }

    var didDisplayedOriginalDownloadFail: Bool {
        failedDownloadPicID != nil && failedDownloadPicID == displayedPicID
    }

    var orientationEdits: [String: PicOrientationEdit] = [:]

    @ObservationIgnored var imageCache: [String: UIImage] = [:]
    @ObservationIgnored var orientationSessions: [String: OrientationEditSession] = [:]
    @ObservationIgnored private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let downloadMonitor = CloudDownloadMonitor()

    /// Maximum number of full-resolution images to keep cached around the current index.
    private let cacheWindow = 5

    func clearDisplay() {
        displayedPicID = ""
        displayedPic = nil
        displayedThumbnail = nil
        displayedImage = nil
        isFullImageLoaded = false
        downloadingOriginalPicID = nil
        downloadProgress = nil
        failedDownloadPicID = nil
        downloadMonitor.stop()
        videoPlayer?.pause()
        videoPlayer = nil
        displayedVideoURL = nil
        allPics = []
        currentIndex = 0
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        imageCache = imageCache.filter { orientationSessions[$0.key] != nil }
    }

    func previewImage(at index: Int) -> UIImage? {
        guard index >= 0, index < allPics.count else { return nil }
        let pic = allPics[index]
        return imageCache[pic.id]
            ?? ThumbnailCache.shared.image(forKey: pic.id)
            ?? pic.thumbnailData.flatMap { UIImage(data: $0) }
    }

    func removeDisplayedPicAndShowNeighbor() -> Bool {
        let removedID = displayedPicID
        let removedIndex = currentIndex
        discardOrientationEdits(forPicIDs: [removedID])
        allPics.removeAll { $0.id == removedID }
        imageCache.removeValue(forKey: removedID)
        prefetchTasks.removeValue(forKey: removedID)?.cancel()
        guard !allPics.isEmpty else {
            clearDisplay()
            return false
        }
        navigateTo(index: min(removedIndex, allPics.count - 1))
        return true
    }

    func removePics(withIDs deletedIDs: Set<String>) {
        discardOrientationEdits(forPicIDs: deletedIDs)
        if deletedIDs.contains(displayedPicID) {
            clearDisplay()
            return
        }
        allPics.removeAll { deletedIDs.contains($0.id) }
        if let displayedPic,
           let newIndex = allPics.firstIndex(where: { $0.id == displayedPic.id }) {
            currentIndex = newIndex
        }
        for id in deletedIDs {
            imageCache.removeValue(forKey: id)
            prefetchTasks.removeValue(forKey: id)?.cancel()
        }
    }

    func setDisplay(_ pic: Pic, completion: @escaping @MainActor @Sendable () -> Void) {
        Self.incrementPicOpenCount()

        // Show thumbnail immediately to open viewer without delay
        let thumbnail: UIImage? = ThumbnailCache.shared.image(forKey: pic.id)
            ?? pic.thumbnailData.flatMap { UIImage(data: $0) }

        displayedThumbnail = thumbnail
        displayedPic = pic
        displayedPicID = pic.id
        isFullImageLoaded = false

        videoPlayer?.pause()
        videoPlayer = nil
        displayedVideoURL = nil

        if pic.isVideo {
            loadVideo(for: pic)
            isFullImageLoaded = true
        } else if let cachedImage = imageCache[pic.id] {
            displayedImage = cachedImage
            isFullImageLoaded = true
        } else {
            displayedImage = nil
        }

        // Navigate immediately — viewer opens with thumbnail
        completion()

        if !pic.isVideo && !isFullImageLoaded {
            loadFullImage(for: pic.id)
        }
    }

    func setDisplay(_ pic: Pic, in pics: [Pic], completion: @escaping @MainActor @Sendable () -> Void) {
        allPics = pics
        currentIndex = pics.firstIndex(where: { $0.id == pic.id }) ?? 0
        setDisplay(pic, completion: completion)
    }

    func navigateTo(index: Int) {
        guard index >= 0, index < allPics.count else { return }
        currentIndex = index
        let pic = allPics[index]

        let thumbnail: UIImage? = ThumbnailCache.shared.image(forKey: pic.id)
            ?? pic.thumbnailData.flatMap { UIImage(data: $0) }

        displayedThumbnail = thumbnail
        displayedPic = pic
        displayedPicID = pic.id
        isFullImageLoaded = false

        videoPlayer?.pause()
        videoPlayer = nil
        displayedVideoURL = nil

        if pic.isVideo {
            loadVideo(for: pic)
            isFullImageLoaded = true
        } else if let cachedImage = imageCache[pic.id] {
            displayedImage = cachedImage
            isFullImageLoaded = true
        } else {
            displayedImage = nil
            loadFullImage(for: pic.id)
        }
    }

    func navigateToNext() {
        if hasNext {
            navigateTo(index: currentIndex + 1)
        }
    }

    func navigateToPrevious() {
        if hasPrevious {
            navigateTo(index: currentIndex - 1)
        }
    }

    private func loadVideo(for pic: Pic) {
        let picID = pic.id
        Task {
            if let localURL = await DataActor.shared.videoURL(forPicWithID: picID) {
                guard self.displayedPicID == picID else { return }
                self.displayedVideoURL = localURL
                self.videoPlayer = AVPlayer(url: localURL)
                return
            }

            if self.displayedPicID == picID {
                withAnimation(.smooth.speed(2.0)) {
                    self.downloadingOriginalPicID = picID
                    self.failedDownloadPicID = nil
                }
                self.downloadProgress = nil
                if let fileName = await OriginalsManager.shared.cloudOriginalFilename(
                    picID: picID, in: DataActor.shared.collectionID
                ) {
                    self.downloadMonitor.start(fileName: fileName) { [weak self] fraction in
                        guard let self, self.downloadingOriginalPicID == picID else { return }
                        self.downloadProgress = fraction
                    }
                }
            }

            let url = await OriginalsManager.shared.materializedVideoURL(
                picID: picID, in: DataActor.shared.collectionID
            )

            if self.downloadingOriginalPicID == picID {
                self.downloadMonitor.stop()
                withAnimation(.smooth.speed(2.0)) {
                    self.downloadingOriginalPicID = nil
                    self.downloadProgress = nil
                    if url == nil {
                        self.failedDownloadPicID = picID
                    }
                }
            }

            guard self.displayedPicID == picID, let url else { return }
            self.displayedVideoURL = url
            self.videoPlayer = AVPlayer(url: url)
        }
    }

    private func loadFullImage(for picID: String) {
        Task(priority: .userInitiated) {
            var loadedImage: UIImage?
            var data = await DataActor.shared.imageData(forPicWithID: picID)
            if data == nil {
                if self.displayedPicID == picID {
                    withAnimation(.smooth.speed(2.0)) {
                        self.downloadingOriginalPicID = picID
                        self.failedDownloadPicID = nil
                    }
                    self.downloadProgress = nil
                    self.downloadMonitor.start(fileName: picID) { [weak self] fraction in
                        guard let self, self.downloadingOriginalPicID == picID else { return }
                        self.downloadProgress = fraction
                    }
                }
                data = await OriginalsManager.shared.fetchOriginal(picID: picID,
                                                                   in: DataActor.shared.collectionID)
                if self.downloadingOriginalPicID == picID {
                    self.downloadMonitor.stop()
                    withAnimation(.smooth.speed(2.0)) {
                        self.downloadingOriginalPicID = nil
                        self.downloadProgress = nil
                        if data == nil {
                            self.failedDownloadPicID = picID
                        }
                    }
                }
            }
            if let data, let image = await UIImage(data: data)?.byPreparingForDisplay() {
                loadedImage = image
            }
            self.imageCache[picID] = loadedImage
            if self.displayedPicID == picID {
                self.displayedImage = loadedImage
                self.isFullImageLoaded = true
                prefetchAdjacentImages()
                evictDistantCacheEntries()
            }
        }
    }

    private func prefetchAdjacentImages() {
        cancelStalePrefetchTasks()

        let indicesToPrefetch = [currentIndex - 1, currentIndex + 1]
        for index in indicesToPrefetch {
            guard index >= 0, index < allPics.count else { continue }
            let pic = allPics[index]
            guard imageCache[pic.id] == nil, prefetchTasks[pic.id] == nil else { continue }
            let picID = pic.id
            let task = Task.detached(priority: .utility) {
                if let data = await DataActor.shared.imageData(forPicWithID: picID),
                   let image = await UIImage(data: data)?.byPreparingForDisplay() {
                    _ = await MainActor.run {
                        self.imageCache[picID] = image
                        self.prefetchTasks.removeValue(forKey: picID)
                    }
                } else {
                    _ = await MainActor.run {
                        self.prefetchTasks.removeValue(forKey: picID)
                    }
                }
            }
            prefetchTasks[picID] = task
        }
    }

    private func cancelStalePrefetchTasks() {
        let adjacentIDs: Set<String> = {
            var ids = Set<String>()
            for offset in -1...1 {
                let index = currentIndex + offset
                if index >= 0, index < allPics.count {
                    ids.insert(allPics[index].id)
                }
            }
            return ids
        }()

        for (picID, task) in prefetchTasks where !adjacentIDs.contains(picID) {
            task.cancel()
            prefetchTasks.removeValue(forKey: picID)
        }
    }

    private func evictDistantCacheEntries() {
        guard !allPics.isEmpty else { return }
        let keepRange = max(0, currentIndex - cacheWindow)...min(allPics.count - 1, currentIndex + cacheWindow)
        let keepIDs = Set(allPics[keepRange].map(\.id))

        for key in imageCache.keys where !keepIDs.contains(key) && orientationSessions[key] == nil {
            imageCache.removeValue(forKey: key)
        }
    }

    static func incrementPicOpenCount() {
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        let count = (defaults?.integer(forKey: picOpenCountKey) ?? 0) + 1
        defaults?.set(count, forKey: picOpenCountKey)
    }

    static var picOpenCount: Int {
        UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")?.integer(forKey: picOpenCountKey) ?? 0
    }
}
