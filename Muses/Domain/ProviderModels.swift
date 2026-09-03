import Foundation

struct ConnectionResult: Codable, Sendable {
    let reachable: Bool
    let model: String
}

struct FactExtractionInput: Sendable {
    let productName: String
    let sellingPoint: String
    let referenceImageURLs: [URL]
    let idempotencyKey: UUID
}

struct ProductFactDraft: Codable, Sendable {
    let category: String?
    let material: String?
    let specification: String?
    let colors: [String]
    let visiblePatterns: [String]
    let visibleText: [String]
    let lockedFeatures: [String]
    let uncertainFields: [String]
}

enum ImageFormat: String, Codable, Sendable {
    case png, jpeg
}

struct ImageGenerationInput: Sendable {
    let prompt: String
    let referenceImageURLs: [URL]
    let outputFormat: ImageFormat
    let idempotencyKey: UUID
}

struct ImageGenerationResult: Sendable {
    let remoteRequestID: String?
    let remoteURL: URL?
    let base64: String?
    let mimeType: String
    let revisedPrompt: String?
}

struct VideoGenerationInput: Sendable {
    let imageURL: URL
    let prompt: String
    let idempotencyKey: UUID
}

struct RemoteVideoJob: Codable, Sendable {
    let taskID: String
    let status: RemoteVideoStatus
}

enum RemoteVideoStatus: String, Codable, Sendable {
    case queued, processing, succeeded, failed, cancelled, unknown
}

struct RemoteVideoJobStatus: Codable, Sendable {
    let taskID: String
    let status: RemoteVideoStatus
    let progress: Double?
    let resultURL: URL?
    let safeError: String?
}

struct CopyGenerationInput: Sendable {
    let facts: ProductSnapshot
    let creativeSummary: String
    let prohibitedClaims: [String]
    let idempotencyKey: UUID
}

struct FactClaim: Codable, Sendable {
    let claim: String
    let sourceField: String
}

struct CopyPackageDraft: Codable, Sendable {
    let titles: [String]
    let body: String
    let topics: [String]
    let factClaims: [FactClaim]
    let warnings: [String]
}

protocol MediaProvider: Sendable {
    func testConnection() async throws -> ConnectionResult
    func extractProductFacts(_ input: FactExtractionInput) async throws -> ProductFactDraft
    func generateImage(_ input: ImageGenerationInput) async throws -> ImageGenerationResult
    func createVideo(_ input: VideoGenerationInput) async throws -> RemoteVideoJob
    func getVideoJob(taskID: String) async throws -> RemoteVideoJobStatus
    func generateCopy(_ input: CopyGenerationInput) async throws -> CopyPackageDraft
}
