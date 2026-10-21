import BackgroundTasks
import Foundation

@MainActor
final class ImportBackgroundTaskController {

    nonisolated static let identifierPrefix = "com.tsubuzaki.IllustMate.import"

#if !targetEnvironment(macCatalyst)
    private var task: BGContinuedProcessingTask?
    private var lastCompleted: Int = 0
    private var lastTotal: Int = 0

    func submit() {
        complete(success: false)
        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString)"
        // Continued processing tasks are registered on demand with a unique identifier per submission;
        // registering the same identifier twice raises an exception.
        let isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: .main
        ) { task in
            MainActor.assumeIsolated {
                ImportManager.shared.backgroundTaskController.attach(task)
            }
        }
        guard isRegistered else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: String(localized: "Import.BackgroundTask.Title", table: "Import"),
            subtitle: String(localized: "Import.Importing", table: "Import")
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            debugPrint("Could not submit import background task: \(error.localizedDescription)")
        }
    }

    func update(completed: Int, total: Int) {
        lastCompleted = completed
        lastTotal = total
        guard let task else { return }
        task.progress.totalUnitCount = Int64(total)
        task.progress.completedUnitCount = Int64(completed)
        task.updateTitle(
            String(localized: "Import.BackgroundTask.Title", table: "Import"),
            subtitle: String(localized: "Import.BackgroundTask.Subtitle.\(completed).\(total)", table: "Import")
        )
    }

    func complete(success: Bool) {
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func attach(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask, ImportManager.shared.isRunning else {
            task.setTaskCompleted(success: true)
            return
        }
        self.task?.setTaskCompleted(success: false)
        self.task = task
        task.expirationHandler = {
            Task { @MainActor in
                ImportManager.shared.interrupt()
            }
        }
        update(completed: lastCompleted, total: lastTotal)
    }
#else
    func submit() { }
    func update(completed: Int, total: Int) { }
    func complete(success: Bool) { }
#endif
}
