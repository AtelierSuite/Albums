import Foundation

nonisolated enum ImportJobStore {

    private static let jobFilename = "job.json"
    private static let progressFilename = "progress.json"
    private static let stagingFolderName = "Files"

    static var rootURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("PendingImports", isDirectory: true)
    }

    static func directoryURL(for jobID: UUID) -> URL {
        rootURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    static func stagingURL(for jobID: UUID) -> URL {
        directoryURL(for: jobID).appendingPathComponent(stagingFolderName, isDirectory: true)
    }

    static func stagedFileURL(named name: String, for jobID: UUID) -> URL {
        stagingURL(for: jobID).appendingPathComponent(name)
    }

    static func prepareStaging(for jobID: UUID) throws {
        try FileManager.default.createDirectory(
            at: stagingURL(for: jobID), withIntermediateDirectories: true
        )
    }

    static func stageData(_ data: Data, for jobID: UUID, pathExtension: String) throws -> String {
        try prepareStaging(for: jobID)
        let name = pathExtension.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(pathExtension)"
        try data.write(to: stagedFileURL(named: name, for: jobID), options: .atomic)
        return name
    }

    static func stageFile(at url: URL, for jobID: UUID) throws -> String {
        try prepareStaging(for: jobID)
        let pathExtension = url.pathExtension
        let name = pathExtension.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(pathExtension)"
        try FileManager.default.copyItem(at: url, to: stagedFileURL(named: name, for: jobID))
        return name
    }

    static func save(_ job: ImportJob) throws {
        try FileManager.default.createDirectory(
            at: directoryURL(for: job.id), withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(job)
        try data.write(to: directoryURL(for: job.id).appendingPathComponent(jobFilename), options: .atomic)
    }

    static func save(_ progress: ImportJobProgress, for jobID: UUID) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(
            to: directoryURL(for: jobID).appendingPathComponent(progressFilename), options: .atomic
        )
    }

    static func progress(for jobID: UUID) -> ImportJobProgress {
        let url = directoryURL(for: jobID).appendingPathComponent(progressFilename)
        guard let data = try? Data(contentsOf: url),
              let progress = try? JSONDecoder().decode(ImportJobProgress.self, from: data) else {
            return ImportJobProgress()
        }
        return progress
    }

    static func pendingJobs() -> [ImportJob] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        let orphanCutoff = Date.now.addingTimeInterval(-3600)
        var jobs: [ImportJob] = []
        for directory in directories {
            let url = directory.appendingPathComponent(jobFilename)
            if let data = try? Data(contentsOf: url),
               let job = try? JSONDecoder().decode(ImportJob.self, from: data) {
                jobs.append(job)
            } else if let created = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      created < orphanCutoff {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        return jobs.sorted { $0.dateCreated < $1.dateCreated }
    }

    static func remove(_ jobID: UUID) {
        try? FileManager.default.removeItem(at: directoryURL(for: jobID))
    }
}
