@preconcurrency import Photos
import Foundation

struct PhotoSaveResult: Sendable {
    let localIdentifier: String?
}

protocol PhotoLibraryServing: Sendable {
    func saveImage(at url: URL) async throws -> PhotoSaveResult
    func saveVideo(at url: URL) async throws -> PhotoSaveResult
}

final class PhotoLibraryService: PhotoLibraryServing, @unchecked Sendable {
    func saveImage(at url: URL) async throws -> PhotoSaveResult {
        try await save(resourceURL: url, type: .photo)
    }

    func saveVideo(at url: URL) async throws -> PhotoSaveResult {
        try await save(resourceURL: url, type: .video)
    }

    private func save(resourceURL: URL, type: PHAssetResourceType) async throws -> PhotoSaveResult {
        guard FileManager.default.isReadableFile(atPath: resourceURL.path) else {
            throw AppError.safe("ASSET_NOT_FOUND", "本地媒体文件不存在")
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.safe("SAVE_PERMISSION_DENIED", "需要照片写入权限才能保存结果")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let identifier = SendableLockedBox<String?>(nil)
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: type, fileURL: resourceURL, options: nil)
                identifier.value = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, _ in
                if success { continuation.resume(returning: PhotoSaveResult(localIdentifier: identifier.value)) }
                else { continuation.resume(throwing: AppError.safe("PHOTO_SAVE_FAILED", "媒体保存到相册失败", retryable: true)) }
            }
        }
    }
}

final class SendableLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
