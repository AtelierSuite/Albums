import SwiftUI
import UIKit

@MainActor @Observable
public final class SaveSession {

    public enum Phase {
        case idle
        case checking
        case duplicates([DuplicateMatch])
        case saving
        case saved
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public let items: [SharedItem]
    public let failedItemCount: Int
    private let close: @MainActor () -> Void
    private var pendingDestination: SaveDestination?

    public init(items: [SharedItem], failedItemCount: Int, close: @escaping @MainActor () -> Void) {
        self.items = items
        self.failedItemCount = failedItemCount
        self.close = close
    }

    public var destinationTitle: String? {
        pendingDestination?.title
    }

    public func save(to destination: SaveDestination) async {
        pendingDestination = destination
        withAnimation(.smooth.speed(2.0)) { phase = .checking }
        let matches = await DuplicateChecker.matches(for: items, in: destination)
        if matches.isEmpty {
            await perform(items, to: destination)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.smooth.speed(2.0)) { phase = .duplicates(matches) }
        }
    }

    public func resolveDuplicates(skippingDuplicates: Bool) async {
        guard let destination = pendingDestination, case .duplicates(let matches) = phase else { return }
        let skipped = skippingDuplicates ? Set(matches.map(\.itemIndex)) : []
        let remaining = items.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
        if remaining.isEmpty {
            finish()
        } else {
            await perform(remaining, to: destination)
        }
    }

    public func cancel() {
        close()
    }

    private func perform(_ items: [SharedItem], to destination: SaveDestination) async {
        withAnimation(.smooth.speed(2.0)) { phase = .saving }
        do {
            switch destination {
            case .albums(let libraryID, _, let albumID, _):
                try await LibrarySaver.save(items, toLibrary: libraryID, albumID: albumID)
            case .photos(let collectionIDs, _):
                guard await PhotosSaver.authorize() else { throw PhotosSaver.NoAccess() }
                try await PhotosSaver.save(items, toCollectionsWithIDs: collectionIDs)
            }
            LastUsedDestination.current = destination
            finish()
        } catch is LibrarySaver.MissingAlbum {
            fail(String(localized: "Saving.Failed.MissingAlbum", table: "Saving", bundle: .engine))
        } catch is PhotosSaver.MissingAlbums {
            fail(String(localized: "Saving.Failed.MissingAlbum", table: "Saving", bundle: .engine))
        } catch is PhotosSaver.NoAccess {
            fail(String(localized: "Saving.Failed.NoPhotosAccess", table: "Saving", bundle: .engine))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let defaults = UserDefaults(suiteName: "group.com.tsubuzaki.IllustMate")
        guard defaults?.object(forKey: "ShareSheetShowAnimation") as? Bool ?? true else {
            close()
            return
        }
        withAnimation(.smooth.speed(2.0)) { phase = .saved }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            close()
        }
    }

    private func fail(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(.smooth.speed(2.0)) { phase = .failed(message) }
    }
}
