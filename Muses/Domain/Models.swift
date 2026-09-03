import Foundation

typealias MusesID = UUID

enum ProductStatus: String, Codable, Sendable {
    case draft, factsPending, factsConfirmed, creating, completed, failed
}

enum Platform: String, Codable, Sendable {
    case xiaohongshu
}

enum CreativeTemplate: String, Codable, Sendable {
    case handheldLifestyleV1 = "handheld_lifestyle_v1"
}

enum CreationStatus: String, Codable, Sendable {
    case draft, generatingImage, imageReview, generatingVideo, videoReview, generatingCopy, ready, saved, failed
}

enum GenerationKind: String, Codable, Sendable {
    case productFacts, image, video, copy
}

enum JobStatus: String, Codable, Sendable {
    case draft, submitting, submissionUnknown = "submission_unknown", queued, processing, downloading
    case needsReview = "needs_review"
    case succeeded, failed, cancelled, unknown

    var canCreateReplacement: Bool {
        self == .failed || self == .cancelled
    }

    var shouldResume: Bool {
        [.queued, .processing, .downloading, .unknown].contains(self)
    }
}

enum FactField: String, Codable, Sendable, CaseIterable, Hashable {
    case category, material, specification, colors, patterns, visibleText, audience, sellingPoint, lockedFeatures
}

enum FactConfirmationStatus: String, Codable, Sendable, Equatable {
    case pending, confirmed, notApplicable
}

enum JobStateMachine {
    static func canTransition(from: JobStatus, to: JobStatus) -> Bool {
        if from == to { return true }
        let allowed: [JobStatus: Set<JobStatus>] = [
            .draft: [.submitting, .cancelled],
            .submitting: [.submissionUnknown, .queued, .processing, .downloading, .needsReview, .unknown, .succeeded, .failed, .cancelled],
            .submissionUnknown: [.submitting, .processing, .downloading, .needsReview, .succeeded, .failed, .cancelled],
            .queued: [.processing, .downloading, .unknown, .failed, .cancelled],
            .processing: [.submissionUnknown, .downloading, .unknown, .failed, .cancelled],
            .downloading: [.needsReview, .succeeded, .unknown, .failed, .cancelled],
            .needsReview: [.succeeded, .failed],
            .unknown: [.submissionUnknown, .queued, .processing, .downloading, .needsReview, .succeeded, .failed, .cancelled],
            .succeeded: [],
            .failed: [],
            .cancelled: []
        ]
        return allowed[from]?.contains(to) == true
    }

    static func transition(_ job: inout GenerationJob, to status: JobStatus) throws {
        guard canTransition(from: job.status, to: status) else {
            throw AppError.safe("JOB_TRANSITION_INVALID", "生成任务状态异常", context: ["from": job.status.rawValue, "to": status.rawValue])
        }
        job.status = status
        if status == .submitting { job.submittedAt = job.submittedAt ?? .now }
        if [.queued, .processing, .unknown].contains(status) { job.lastPolledAt = .now }
    }
}

enum ReviewResult: String, Codable, Sendable {
    case approved, rejected
}

enum ReviewIssue: String, Codable, Sendable, CaseIterable {
    case shapeChanged, wrongColor, wrongPattern, wrongText, wrongMaterial, addedObject, deformation, abnormalContact, backgroundJump, other
}

enum AssetKind: String, Codable, Sendable {
    case sourceImage, generatedImage, generatedVideo, livePhotoImage, livePhotoVideo
}

struct Product: Codable, Identifiable, Sendable {
    let id: MusesID
    var name: String
    let createdAt: Date
    var currentSnapshotID: MusesID
    var status: ProductStatus
}

struct ProductSnapshot: Codable, Identifiable, Sendable {
    let id: MusesID
    let productID: MusesID
    let sourceAssetIDs: [MusesID]
    var category: String?
    var material: String?
    var specification: String?
    var colors: [String]
    var visiblePatterns: [String]
    var visibleText: [String]
    var audience: String?
    var verifiedSellingPoints: [String]
    var lockedFeatures: [String]
    var uncertainFields: [String]
    var rightsConfirmed: Bool
    var confirmedAt: Date?
    var fieldConfirmations: [String: FactConfirmationStatus]? = nil
}

struct Creation: Codable, Identifiable, Sendable {
    let id: MusesID
    let productSnapshotID: MusesID
    let platform: Platform
    let template: CreativeTemplate
    var imageJobID: MusesID? = nil
    var videoJobID: MusesID? = nil
    var copyJobID: MusesID? = nil
    var status: CreationStatus
    let createdAt: Date
    var updatedAt: Date
}

struct GenerationJob: Codable, Identifiable, Sendable {
    let id: MusesID
    let kind: GenerationKind
    var creationID: MusesID? = nil
    var providerTaskID: String? = nil
    var providerResultURL: String? = nil
    let idempotencyKey: UUID
    let model: String
    var promptVersionID: MusesID? = nil
    var status: JobStatus
    var submittedAt: Date? = nil
    var lastPolledAt: Date? = nil
    var errorCode: String? = nil
    var safeErrorMessage: String? = nil
    var outputAssetIDs: [MusesID] = []
}

struct ReviewDecision: Codable, Identifiable, Sendable {
    let id: MusesID
    let assetID: MusesID
    let result: ReviewResult
    let issueTypes: [ReviewIssue]
    let note: String?
    let createdAt: Date
}

struct LocalAsset: Codable, Identifiable, Sendable {
    let id: MusesID
    let kind: AssetKind
    let relativePath: String
    let mimeType: String
    let byteCount: Int64
    let sha256: String
    let createdAt: Date
    var productSnapshotID: MusesID? = nil
    var promptVersionID: MusesID? = nil
    var photosLocalIdentifier: String? = nil
}

struct PromptVersion: Codable, Identifiable, Sendable {
    let id: MusesID
    let productSnapshotID: MusesID
    let templateVersion: String
    let prompt: String
    let negativeConstraints: [String]
    let precedingReviewIssues: [ReviewIssue]
    let model: String
    let providerSchemaVersion: Int
    let parameters: [String: String]
    let createdAt: Date
}

struct StoredCopyPackage: Codable, Identifiable, Sendable {
    let id: MusesID
    let creationID: MusesID
    var titles: [String]
    var selectedTitleIndex: Int
    var body: String
    var topics: [String]
    let createdAt: Date
    var updatedAt: Date
}

enum ExportItemStatus: String, Codable, Sendable {
    case notRequested, saving, saved, failed
}

struct ExportRecord: Codable, Identifiable, Sendable {
    let id: MusesID
    let creationID: MusesID
    var livePhotoStatus: ExportItemStatus
    var livePhotoLocalIdentifier: String? = nil
    var imageStatus: ExportItemStatus
    var imageLocalIdentifier: String? = nil
    var videoStatus: ExportItemStatus
    var videoLocalIdentifier: String? = nil
    var copyStatus: ExportItemStatus
    let createdAt: Date
    var updatedAt: Date
}

struct AppSnapshot: Codable, Sendable {
    var schemaVersion: Int = 2
    var products: [Product] = []
    var productSnapshots: [ProductSnapshot] = []
    var creations: [Creation] = []
    var jobs: [GenerationJob] = []
    var reviews: [ReviewDecision] = []
    var assets: [LocalAsset] = []
    var promptVersions: [PromptVersion] = []
    var copyPackages: [StoredCopyPackage] = []
    var exportRecords: [ExportRecord] = []
    var updatedAt: Date = .now
}

struct AppError: Error, Codable, Sendable, LocalizedError {
    let code: String
    let userMessage: String
    let retryable: Bool
    let safeContext: [String: String]

    var errorDescription: String? { userMessage }

    static func safe(_ code: String, _ message: String, retryable: Bool = false, context: [String: String] = [:]) -> AppError {
        AppError(code: code, userMessage: message, retryable: retryable, safeContext: context)
    }
}
