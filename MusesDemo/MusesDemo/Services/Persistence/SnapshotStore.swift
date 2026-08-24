import Foundation

actor SnapshotStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appending(path: "Muses", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "snapshot-v2.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> AppSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppSnapshot() }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let snapshot = try decoder.decode(AppSnapshot.self, from: data)
            guard snapshot.schemaVersion == 2 else {
                throw AppError.safe("PERSISTENCE_SCHEMA_UNSUPPORTED", "本地数据版本暂不支持", context: ["schema": String(snapshot.schemaVersion)])
            }
            return snapshot
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.safe("PERSISTENCE_READ_FAILED", "无法读取本地项目", retryable: true)
        }
    }

    func save(_ snapshot: AppSnapshot) throws {
        do {
            var value = snapshot
            value.updatedAt = .now
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw AppError.safe("PERSISTENCE_WRITE_FAILED", "无法保存本地项目", retryable: true)
        }
    }

    @discardableResult
    func update(_ mutation: @Sendable (inout AppSnapshot) throws -> Void) throws -> AppSnapshot {
        var snapshot = try load()
        try mutation(&snapshot)
        try save(snapshot)
        return snapshot
    }

    /// 持久化远端任务 ID 后才返回，调用方随后才能刷新 UI。
    func recordRemoteVideoTask(localJobID: MusesID, providerTaskID: String, status: JobStatus) throws -> AppSnapshot {
        try update { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == localJobID }) else {
                throw AppError.safe("JOB_NOT_FOUND", "找不到本地生成任务")
            }
            snapshot.jobs[index].providerTaskID = providerTaskID
            try JobStateMachine.transition(&snapshot.jobs[index], to: status)
            snapshot.jobs[index].submittedAt = snapshot.jobs[index].submittedAt ?? .now
        }
    }

    func resumableVideoJobs() throws -> [GenerationJob] {
        try load().jobs.filter { $0.kind == .video && $0.providerTaskID != nil && $0.status.shouldResume }
    }

    /// 修复进程在生命周期回调前被终止后遗留的提交态，不创建新任务。
    func normalizeInterruptedSubmissions() throws -> AppSnapshot {
        try update { snapshot in
            for index in snapshot.jobs.indices where snapshot.jobs[index].status == .submitting {
                let job = snapshot.jobs[index]
                if job.kind == .video, job.providerTaskID != nil {
                    try JobStateMachine.transition(&snapshot.jobs[index], to: .processing)
                } else if job.providerResultURL != nil {
                    try JobStateMachine.transition(&snapshot.jobs[index], to: .downloading)
                } else {
                    try JobStateMachine.transition(&snapshot.jobs[index], to: .submissionUnknown)
                }
            }
        }
    }

    /// Provider 支持幂等键时，用同一个本地任务和同一把幂等键重新进入提交态。
    func prepareIdempotentResubmission(localJobID: MusesID) throws -> AppSnapshot {
        try update { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == localJobID }),
                  snapshot.jobs[index].status == .submissionUnknown else {
                throw AppError.safe("JOB_NOT_RESUBMITTABLE", "当前任务不能安全重试")
            }
            try JobStateMachine.transition(&snapshot.jobs[index], to: .submitting)
        }
    }
}
