import CoreImage
import CoreImage.CIFilterBuiltins
import Engine
import Foundation
import SwiftUI

extension AlbumView {

    func reloadPreferencesAndRefreshData() async {
        await loadPreferences()
        await MainActor.run {
            albumStyleState = albumStyle
            albumSortState = albumSort
        }
        await refreshData()
    }

    func refreshData() async {
        await withTaskGroup(of: Void.self) { group in
            if let currentAlbum {
                group.addTask {
                    if let album = await DataActor.shared.album(for: currentAlbum.id) {
                        await MainActor.run {
                            self.currentAlbum = album
                        }
                    }
                }
            }
            group.addTask {
                let albums = await self.fetchAlbums()
                let totalAlbumCount = await DataActor.shared.albumCount()
                await MainActor.run {
                    withAnimation {
                        self.albums = albums
                    }
                    self.totalAlbumCount = totalAlbumCount
                    self.hasFetchedAlbums = true
                }
                await AlbumCoverCache.shared.loadCovers(for: albums)
            }
            group.addTask {
                // Fetch count first for immediate placeholder layout
                let count = await DataActor.shared.picCount(in: self.currentAlbum)
                await MainActor.run {
                    self.picCount = count
                    self.hasFetchedPicCount = true
                }
                // Then fetch all skeletons (lightweight — no blob data)
                let pics = await self.fetchPics()
                await MainActor.run {
                    withAnimation(.smooth.speed(2.0)) {
                        self.pics = pics
                    }
                    self.hasFetchedPics = true
                }
            }
        }
    }

    func revealPicIfNeeded(with proxy: ScrollViewProxy) {
        guard let request = navigation.picRevealRequest,
              request.albumID == currentAlbum?.id,
              hasFetchedPics,
              pics.contains(where: { $0.id == request.picID }) else { return }
        navigation.picRevealRequest = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.smooth) {
                proxy.scrollTo(request.picID, anchor: .center)
            }
            withAnimation(.smooth.speed(2.0)) {
                highlightedPicID = request.picID
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth) {
                highlightedPicID = nil
            }
        }
    }

    func fetchAlbums() async -> [Album] {
        do {
            return try await DataActor.shared.albumsWithCounts(in: currentAlbum, sortedBy: albumSort)
        } catch {
            debugPrint(error.localizedDescription)
            return []
        }
    }

    func refreshAlbumsAndSet() {
        Task.detached(priority: .userInitiated) {
            let albums = await fetchAlbums()
            let totalAlbumCount = await DataActor.shared.albumCount()
            await MainActor.run {
                withAnimation {
                    self.albums = albums
                }
                self.totalAlbumCount = totalAlbumCount
            }
            await AlbumCoverCache.shared.loadCovers(for: albums)
        }
    }

    func fetchPics() async -> [Pic] {
        let pics = await fetchSortedPics()
        return pics.filter(\.isPinned) + pics.filter { !$0.isPinned }
    }

    func fetchSortedPics() async -> [Pic] {
        do {
            switch picSortType {
            case .dateAddedAscending:
                return try await DataActor.shared.picSkeletons(
                    in: currentAlbum, order: .forward
                )
            case .dateAddedDescending:
                return try await DataActor.shared.picSkeletons(
                    in: currentAlbum, order: .reverse
                )
            case .nameAscending:
                return try await DataActor.shared.picSkeletonsByName(
                    in: currentAlbum, order: .forward
                )
            case .nameDescending:
                return try await DataActor.shared.picSkeletonsByName(
                    in: currentAlbum, order: .reverse
                )
            case .prominentColor:
                let pics = try await DataActor.shared.pics(
                    in: currentAlbum, order: .reverse
                )
                return await sortPicsByProminentColor(pics)
            }
        } catch {
            debugPrint(error.localizedDescription)
            return []
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func sortPicsByProminentColor(_ pics: [Pic]) async -> [Pic] {
        let picIDs = pics.map(\.id)
        var colorsMap = await PColorActor.shared.cachedColors(forPicIDs: picIDs)

        let uncachedPics = pics.filter { colorsMap[$0.id] == nil && $0.thumbnailData != nil }

        if !uncachedPics.isEmpty {
            let maxConcurrent = 8
            let newColors: [(picID: String, colors: PicColors)] = await withTaskGroup(
                of: (String, PicColors?).self,
                returning: [(picID: String, colors: PicColors)].self
            ) { group in
                var iterator = uncachedPics.makeIterator()

                for _ in 0..<min(maxConcurrent, uncachedPics.count) {
                    guard let pic = iterator.next() else { break }
                    group.addTask {
                        guard let thumbnailData = pic.thumbnailData else { return (pic.id, nil) }
                        let colors = ProminentColor.calculate(from: thumbnailData)
                        return (pic.id, colors)
                    }
                }

                var results: [(picID: String, colors: PicColors)] = []
                for await (picID, colors) in group {
                    if let colors {
                        results.append((picID: picID, colors: colors))
                    }
                    if let pic = iterator.next() {
                        group.addTask {
                            guard let thumbnailData = pic.thumbnailData else { return (pic.id, nil) }
                            let colors = ProminentColor.calculate(from: thumbnailData)
                            return (pic.id, colors)
                        }
                    }
                }
                return results
            }
            for entry in newColors {
                colorsMap[entry.picID] = entry.colors
            }
            await PColorActor.shared.storeColors(newColors)
        }

        let gray = RGBColor(red: 128, green: 128, blue: 128)
        let defaultColors = PicColors(primary: gray, accent: gray, contrasting: gray)
        return pics.sorted { lhs, rhs in
            (colorsMap[lhs.id] ?? defaultColors) < (colorsMap[rhs.id] ?? defaultColors)
        }
    }

    func refreshPicsAndSet() {
        Task.detached(priority: .userInitiated) {
            let count = await DataActor.shared.picCount(in: self.currentAlbum)
            await MainActor.run {
                self.picCount = count
                self.hasFetchedPicCount = true
            }
            let pics = await self.fetchPics()
            await MainActor.run {
                withAnimation(.smooth.speed(2.0)) {
                    self.pics = pics
                }
                self.hasFetchedPics = true
            }
        }
    }

    func searchAlbums(matching searchText: String) async {
        do {
            let results = try await DataActor.shared.searchAlbums(
                matching: searchText, in: currentAlbum, sortedBy: albumSort
            )
            await MainActor.run {
                withAnimation {
                    self.searchResults = results
                }
            }
        } catch {
            debugPrint(error.localizedDescription)
        }
    }

    func updateBackgroundImage() async {
        guard let currentAlbum, currentAlbum.hasCoverPhoto,
              let coverPhoto = currentAlbum.coverPhoto else {
            await MainActor.run {
                backgroundImage = nil
            }
            return
        }
        let blurred = await Task.detached(priority: .utility) {
            Self.makeBlurredBackground(from: coverPhoto)
        }.value
        guard !Task.isCancelled else { return }
        await MainActor.run {
            backgroundImage = blurred
        }
    }

    private nonisolated static func makeBlurredBackground(from data: Data) -> UIImage? {
        guard let sourceImage = UIImage(data: data) else { return nil }
        // Downscale to a small size since this is just a blurry background
        let targetSize = CGSize(width: 64, height: 64)
        let scaledImage = sourceImage.scalePreservingAspectRatio(targetSize: targetSize)
        guard let ciImage = CIImage(image: scaledImage) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage
        filter.radius = 10
        guard let outputImage = filter.outputImage else { return nil }
        let context = CIContext()
        // Crop to original extent since Gaussian blur expands the image
        let croppedOutput = outputImage.cropped(to: ciImage.extent)
        guard let cgImage = context.createCGImage(croppedOutput, from: croppedOutput.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
