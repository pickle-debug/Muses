@preconcurrency import AVFoundation
@preconcurrency import Photos
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LivePhotoSaveStatus: String, Codable, Sendable {
    case saved
}

struct LivePhotoSaveResult: Sendable {
    let localIdentifier: String?
    let status: LivePhotoSaveStatus
}

protocol LivePhotoServing: Sendable {
    func createAndSave(photoURL: URL, videoURL: URL) async throws -> LivePhotoSaveResult
}

actor LivePhotoService: LivePhotoServing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createAndSave(photoURL: URL, videoURL: URL) async throws -> LivePhotoSaveResult {
        guard fileManager.isReadableFile(atPath: photoURL.path), fileManager.isReadableFile(atPath: videoURL.path) else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片生成失败，MP4 仍可保存")
        }
        let identifier = UUID().uuidString
        let packageDirectory = fileManager.temporaryDirectory.appending(path: "muses-live-photo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: packageDirectory) }
        let pairedPhoto = packageDirectory.appending(path: "paired.jpg")
        let pairedVideo = packageDirectory.appending(path: "paired.mov")

        do {
            try writePairedPhoto(sourceURL: photoURL, destinationURL: pairedPhoto, assetIdentifier: identifier)
            try await writePairedVideo(sourceURL: videoURL, destinationURL: pairedVideo, assetIdentifier: identifier)
            return try await saveToPhotoLibrary(photoURL: pairedPhoto, videoURL: pairedVideo)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片生成失败，MP4 仍可保存", retryable: true)
        }
    }

    private func writePairedPhoto(sourceURL: URL, destinationURL: URL, assetIdentifier: String) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片图片封装失败")
        }
        let existing = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var properties = existing
        var maker = (properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]) ?? [:]
        maker["17"] = assetIdentifier
        properties[kCGImagePropertyMakerAppleDictionary] = maker
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片图片封装失败")
        }
    }

    private func writePairedVideo(sourceURL: URL, destinationURL: URL, assetIdentifier: String) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        guard duration.isValid, duration.seconds > 0,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态文件不包含有效画面")
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let identifierItem = AVMutableMetadataItem()
        identifierItem.keySpace = .quickTimeMetadata
        identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        identifierItem.value = assetIdentifier as NSString
        identifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identifierItem]

        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoDescriptions.first)
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态画面无法封装")
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        var metadataDescription: CMFormatDescription?
        let specification: [CFString: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: kCMMetadataBaseDataType_SInt8 as String
        ]
        let result = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &metadataDescription
        )
        guard result == noErr, let metadataDescription else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片时间元数据创建失败")
        }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metadataDescription)
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片时间元数据无法写入")
        }
        writer.add(metadataInput)

        guard writer.startWriting(), reader.startReading() else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态资源封装无法启动")
        }
        writer.startSession(atSourceTime: .zero)

        let stillItem = AVMutableMetadataItem()
        stillItem.keySpace = .quickTimeMetadata
        stillItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillItem.value = 0 as NSNumber
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let stillTime = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
        let frameDuration = CMTime(value: 1, timescale: 30)
        let group = AVTimedMetadataGroup(items: [stillItem], timeRange: CMTimeRange(start: stillTime, duration: frameDuration))
        guard metadataAdaptor.append(group) else {
            reader.cancelReading()
            writer.cancelWriting()
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片时间元数据写入失败")
        }
        metadataInput.markAsFinished()

        while reader.status == .reading, let buffer = videoOutput.copyNextSampleBuffer() {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
                try Task.checkCancellation()
            }
            guard videoInput.append(buffer) else {
                reader.cancelReading()
                writer.cancelWriting()
                throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态资源写入失败")
            }
        }
        videoInput.markAsFinished()
        guard reader.status == .completed else {
            writer.cancelWriting()
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态资源读取失败")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "动态资源封装失败")
        }
    }

    private func saveToPhotoLibrary(photoURL: URL, videoURL: URL) async throws -> LivePhotoSaveResult {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw AppError.safe("SAVE_PERMISSION_DENIED", "需要照片写入权限才能保存结果")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let localIdentifier = SendableLockedBox<String?>(nil)
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: photoURL, options: options)
                request.addResource(with: .pairedVideo, fileURL: videoURL, options: options)
                localIdentifier.value = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, _ in
                if success {
                    continuation.resume(returning: LivePhotoSaveResult(localIdentifier: localIdentifier.value, status: .saved))
                } else {
                    continuation.resume(throwing: AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片保存失败，MP4 仍可保存", retryable: true))
                }
            }
        }
    }
}
