import Engine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class ImportManager {

    static let shared = ImportManager()

    private(set) var completedCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var isResumedRun: Bool = false
    private(set) var lastFinishedJobID: UUID?
    private(set) var interruptedJobs: [ImportJob] = []
    private(set) var interruptedRemainingCount: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isStopping: Bool = false
    private(set) var isPaused: Bool = false

    @ObservationIgnored private var queue: [ImportJob] = []
    @ObservationIgnored private var pickerItems: [UUID: [String: PhotosPickerItem]] = [:]
    @ObservationIgnored private var waiters: [UUID: [CheckedContinuation<ImportJobResult, Never>]] = [:]
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var stopRequest: StopRequest?
    @ObservationIgnored let backgroundTaskController = ImportBackgroundTaskController()

    private enum StopRequest {
        case interrupt
        case cancel(deletingImported: Bool)
    }

    private init() { }

    func run(_ job: ImportJob, pickerItems items: [String: PhotosPickerItem] = [:]) async -> ImportJobResult {
        guard !job.items.isEmpty else {
            ImportJobStore.remove(job.id)
            return ImportJobResult(jobID: job.id, importedCount: 0, wasCancelled: false)
        }
        do {
            try ImportJobStore.save(job)
        } catch {
            debugPrint("Could not persist import job: \(error.localizedDescription)")
        }
        if !items.isEmpty {
            pickerItems[job.id] = items
        }
        return await withCheckedContinuation { continuation in
            waiters[job.id, default: []].append(continuation)
            queue.append(job)
            startRunnerIfNeeded(isResumed: false)
        }
    }

    func loadInterruptedJobs() {
        guard !isRunning else { return }
        reloadInterruptedJobs()
    }

    private func reloadInterruptedJobs() {
        let jobs = ImportJobStore.pendingJobs()
        interruptedJobs = jobs
        interruptedRemainingCount = jobs.reduce(0) { total, job in
            total + max(job.items.count - ImportJobStore.progress(for: job.id).nextIndex, 0)
        }
    }

    func resumeInterruptedJobs() async {
        let jobs = interruptedJobs
        clearInterruptedJobs()
        guard !jobs.isEmpty else { return }
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined,
           jobs.contains(where: \.containsPhotosAssets) {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        queue.append(contentsOf: jobs)
        startRunnerIfNeeded(isResumed: true)
    }

    func discardInterruptedJobs(deletingImported: Bool) async {
        let jobs = interruptedJobs
        clearInterruptedJobs()
        for job in jobs {
            await discard(job, deletingImported: deletingImported)
        }
        lastFinishedJobID = jobs.last?.id
    }

    func pause() {
        guard isRunning, !isStopping else { return }
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func cancel(deletingImported: Bool) {
        guard isRunning else { return }
        stopRequest = .cancel(deletingImported: deletingImported)
        isStopping = true
        isPaused = false
    }

    func interrupt() {
        guard isRunning else { return }
        stopRequest = .interrupt
        isStopping = true
        isPaused = false
    }

    private func clearInterruptedJobs() {
        interruptedJobs = []
        interruptedRemainingCount = 0
    }

    private func startRunnerIfNeeded(isResumed: Bool) {
        guard runner == nil else { return }
        isResumedRun = isResumed
        stopRequest = nil
        isStopping = false
        isPaused = false
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskController.submit()
        runner = Task {
            await processQueue()
        }
    }

    private func processQueue() async {
        var didFinishAll = true
        while let job = queue.first, stopRequest == nil {
            queue.removeFirst()
            if await !process(job) {
                didFinishAll = false
            }
        }
        if stopRequest != nil {
            didFinishAll = false
        }
        await handleStop()
        completedCount = 0
        totalCount = 0
        isResumedRun = false
        stopRequest = nil
        isStopping = false
        runner = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        backgroundTaskController.complete(success: didFinishAll)
        if !queue.isEmpty {
            startRunnerIfNeeded(isResumed: false)
        }
    }

    private func process(_ job: ImportJob) async -> Bool {
        var progress = ImportJobStore.progress(for: job.id)
        totalCount = job.items.count
        completedCount = min(progress.nextIndex, job.items.count)
        backgroundTaskController.update(completed: completedCount, total: totalCount)

        let dataActor = DataActor.instance(for: job.libraryID)
        let canReadLibrary = ImportItemLoader.canReadPhotoLibrary()
        let jobPickerItems = pickerItems[job.id] ?? [:]

        while true {
            while isPaused && stopRequest == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if stopRequest != nil {
                queue.insert(job, at: 0)
                return false
            }
            guard progress.nextIndex < job.items.count else { break }
            let item = job.items[progress.nextIndex]
            let pickerItem: PhotosPickerItem? = if case .photosAsset(let identifier, _) = item.source {
                jobPickerItems[identifier]
            } else {
                nil
            }
            let picID = await ImportItemLoader.importItem(
                item, jobID: job.id, into: dataActor,
                pickerItem: pickerItem, canReadLibrary: canReadLibrary
            )
            if let picID {
                progress.importedPicIDs.append(picID)
            }
            progress.nextIndex += 1
            ImportJobStore.save(progress, for: job.id)
            completedCount = progress.nextIndex
            backgroundTaskController.update(completed: completedCount, total: totalCount)
        }

        finish(job, progress: progress)
        return true
    }

    private func finish(_ job: ImportJob, progress: ImportJobProgress) {
        ImportJobStore.remove(job.id)
        pickerItems[job.id] = nil
        invalidateCovers(for: job)
        lastFinishedJobID = job.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let importedCount = progress.importedPicIDs.count
        let albumName = job.destinationAlbumName
        Task {
            await ImportNotifications.sendCompleted(count: importedCount, albumName: albumName)
        }
        resumeWaiters(for: job.id, importedCount: progress.importedPicIDs.count, wasCancelled: false)
    }

    private func handleStop() async {
        guard let stopRequest else { return }
        let jobs = queue
        queue = []
        switch stopRequest {
        case .interrupt:
            for job in jobs {
                invalidateCovers(for: job)
                resumeWaiters(for: job.id, importedCount: 0, wasCancelled: true)
            }
            reloadInterruptedJobs()
            if UIApplication.shared.applicationState != .active {
                Task {
                    await ImportNotifications.sendInterrupted()
                }
            }
        case .cancel(let deletingImported):
            for job in jobs {
                await discard(job, deletingImported: deletingImported)
            }
        }
        lastFinishedJobID = jobs.last?.id
    }

    private func discard(_ job: ImportJob, deletingImported: Bool) async {
        let progress = ImportJobStore.progress(for: job.id)
        if deletingImported {
            await Self.deleteImportedContent(
                picIDs: progress.importedPicIDs, albumIDs: job.createdAlbumIDs, in: job.libraryID
            )
        }
        ImportJobStore.remove(job.id)
        pickerItems[job.id] = nil
        invalidateCovers(for: job)
        resumeWaiters(
            for: job.id,
            importedCount: deletingImported ? 0 : progress.importedPicIDs.count,
            wasCancelled: true
        )
    }

    private func resumeWaiters(for jobID: UUID, importedCount: Int, wasCancelled: Bool) {
        let result = ImportJobResult(jobID: jobID, importedCount: importedCount, wasCancelled: wasCancelled)
        for continuation in waiters.removeValue(forKey: jobID) ?? [] {
            continuation.resume(returning: result)
        }
    }

    private func invalidateCovers(for job: ImportJob) {
        for albumID in job.affectedAlbumIDs {
            AlbumCoverCache.shared.removeImages(forAlbumID: albumID)
        }
    }

    private static func deleteImportedContent(
        picIDs: [String], albumIDs: [String], in libraryID: String
    ) async {
        let dataActor = DataActor.instance(for: libraryID)
        if !picIDs.isEmpty {
            await dataActor.deletePics(withIDs: picIDs)
            await HashActor.instance(for: libraryID).deleteHashes(forPicIDs: picIDs)
            await PColorActor.instance(for: libraryID).deleteColors(forPicIDs: picIDs)
            Task.detached {
                await OriginalsManager.shared.deleteCloudOriginals(picIDs: picIDs, in: libraryID)
            }
        }
        for albumID in albumIDs.reversed() {
            await dataActor.deleteAlbum(withID: albumID)
        }
    }
}

extension ImportJob {
    nonisolated var containsPhotosAssets: Bool {
        items.contains { item in
            if case .photosAsset = item.source { return true }
            return false
        }
    }
}
