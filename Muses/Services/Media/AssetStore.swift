@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor AssetStore {
    private let rootURL: URL
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) throws {
        self.session = session
        self.fileManager = fileManager
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        rootURL = support.appending(path: "Muses", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func importSource(from sourceURL: URL, productID: MusesID, preferredFileName: String? = nil) throws -> LocalAsset {
        guard try resourceSize(at: sourceURL) <= 31_457_280,
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw AppError.safe("SOURCE_IMAGE_INVALID", "请选择有效的商品图片，每张不能超过 30 MB。")
        }
        return try storeFile(from: sourceURL, relativeDirectory: "sources/\(productID.uuidString)", kind: .sourceImage, preferredFileName: preferredFileName)
    }

    func importGenerated(from sourceURL: URL, creationID: MusesID, kind: AssetKind, preferredFileName: String? = nil) throws -> LocalAsset {
        let leaf = kind == .generatedVideo ? "videos" : "images"
        return try storeFile(from: sourceURL, relativeDirectory: "generated/\(creationID.uuidString)/\(leaf)", kind: kind, preferredFileName: preferredFileName)
    }

    func storeBase64(_ value: String, creationID: MusesID, mimeType: String, maximumBytes: Int64) throws -> LocalAsset {
        guard let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else {
            throw AppError.safe("IMAGE_RESPONSE_INVALID", "图片生成结果不可用", retryable: true)
        }
        guard !data.isEmpty, Int64(data.count) <= maximumBytes else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "生成图片文件大小异常")
        }
        guard ["image/png", "image/jpeg", "image/heic"].contains(mimeType.lowercased()) else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "生成图片格式不受支持")
        }
        let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "bin"
        let temporary = fileManager.temporaryDirectory.appending(path: "muses-base64-\(UUID().uuidString).\(ext)")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try validateSignature(at: temporary, mimeType: mimeType.lowercased())
        try validateImageSpec(at: temporary)
        return try importGenerated(from: temporary, creationID: creationID, kind: .generatedImage)
    }

    func download(from remoteURL: URL, creationID: MusesID, kind: AssetKind, maximumBytes: Int64, allowedMIMETypes: Set<String>) async throws -> LocalAsset {
        guard remoteURL.scheme?.lowercased() == "https" else {
            throw AppError.safe("ASSET_DOWNLOAD_FAILED", "结果下载地址无效")
        }
        do {
            let (temporaryURL, response) = try await session.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AppError.safe("ASSET_DOWNLOAD_FAILED", "结果下载失败", retryable: true)
            }
            let mime = response.mimeType?.lowercased() ?? "application/octet-stream"
            guard allowedMIMETypes.contains(mime) else {
                throw AppError.safe("ASSET_DOWNLOAD_FAILED", "下载的媒体格式不受支持")
            }
            let size = try resourceSize(at: temporaryURL)
            guard size > 0, size <= maximumBytes else {
                throw AppError.safe("ASSET_DOWNLOAD_FAILED", "下载的媒体文件大小异常")
            }
            try validateSignature(at: temporaryURL, mimeType: mime)
            try await validateGeneratedMedia(at: temporaryURL, kind: kind)
            return try importGenerated(from: temporaryURL, creationID: creationID, kind: kind, preferredFileName: remoteURL.lastPathComponent)
        } catch let error as AppError { throw error }
        catch { throw AppError.safe("ASSET_DOWNLOAD_FAILED", "结果下载失败", retryable: true) }
    }

    func url(for asset: LocalAsset) throws -> URL {
        let url = rootURL.appending(path: asset.relativePath)
        guard url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path), fileManager.fileExists(atPath: url.path) else {
            throw AppError.safe("ASSET_NOT_FOUND", "本地媒体文件不存在")
        }
        return url
    }

    func deleteProject(productID: MusesID, creationIDs: [MusesID]) throws {
        let source = rootURL.appending(path: "sources/\(productID.uuidString)")
        if fileManager.fileExists(atPath: source.path) { try fileManager.removeItem(at: source) }
        for creationID in creationIDs {
            for directory in ["generated", "packages"] {
                let url = rootURL.appending(path: "\(directory)/\(creationID.uuidString)")
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            }
        }
    }

    func cleanTemporaryFiles(olderThan age: TimeInterval = 24 * 60 * 60) throws {
        let directory = rootURL.appending(path: "temp", directoryHint: .isDirectory)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files where ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture) < cutoff {
            try? fileManager.removeItem(at: file)
        }
    }

    private func storeFile(from sourceURL: URL, relativeDirectory: String, kind: AssetKind, preferredFileName: String?) throws -> LocalAsset {
        guard sourceURL.isFileURL, fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw AppError.safe("ASSET_NOT_FOUND", "媒体文件不可读取")
        }
        let byteCount = try resourceSize(at: sourceURL)
        guard byteCount > 0 else { throw AppError.safe("ASSET_INVALID", "媒体文件为空") }
        let hash = try sha256(at: sourceURL)
        let preferredExtension = preferredFileName.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        // Derive the extension from the decoded image container; picker-provided
        // content types and temporary filenames can disagree with the actual bytes.
        let detectedExtension: String = {
            guard kind == .sourceImage,
                  let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let type = CGImageSourceGetType(imageSource),
                  let value = UTType(type as String)?.preferredFilenameExtension else { return "" }
            return value
        }()
        let ext = detectedExtension.isEmpty ? (preferredExtension.isEmpty ? sourceURL.pathExtension : preferredExtension) : detectedExtension
        let directory = rootURL.appending(path: relativeDirectory, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(hash).\(ext.isEmpty ? "bin" : ext.lowercased())"
        let destination = directory.appending(path: fileName)
        if !fileManager.fileExists(atPath: destination.path) {
            let staging = directory.appending(path: ".\(UUID().uuidString).tmp")
            try fileManager.copyItem(at: sourceURL, to: staging)
            try fileManager.moveItem(at: staging, to: destination)
        }
        let relativePath = String(destination.path.dropFirst(rootURL.path.count + 1))
        return LocalAsset(id: UUID(), kind: kind, relativePath: relativePath, mimeType: mimeType(at: destination), byteCount: byteCount, sha256: hash, createdAt: .now)
    }

    private func resourceSize(at url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private func mimeType(at url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private func sha256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1_024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateSignature(at url: URL, mimeType: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 16) ?? Data()
        let valid: Bool
        switch mimeType {
        case "image/png": valid = bytes.starts(with: [0x89, 0x50, 0x4E, 0x47])
        case "image/jpeg": valid = bytes.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/heic", "image/heif", "video/mp4", "video/quicktime": valid = bytes.count >= 12 && String(data: bytes[4..<8], encoding: .ascii) == "ftyp"
        default: valid = false
        }
        guard valid else { throw AppError.safe("ASSET_DOWNLOAD_FAILED", "下载的媒体文件校验失败") }
    }

    private func validateGeneratedMedia(at url: URL, kind: AssetKind) async throws {
        switch kind {
        case .generatedImage:
            try validateImageSpec(at: url)
        case .generatedVideo:
            try await validateVideoSpec(at: url)
        default:
            break
        }
    }

    private func validateImageSpec(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth > 0, rawHeight > 0 else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "生成图片无法读取尺寸")
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        let width = swapsAxes ? rawHeight : rawWidth
        let height = swapsAxes ? rawWidth : rawHeight
        let ratio = width / height
        guard abs(ratio - 0.75) <= 0.015 else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "生成图片不是要求的 3:4 竖图", context: ["width": String(Int(width)), "height": String(Int(height))])
        }
    }

    private func validateVideoSpec(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isValid, duration.seconds >= 2.9, duration.seconds <= 5.1,
              let track = videoTracks.first else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "AI 动态不是要求的 3–5 秒有效视频")
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let width = Int(abs(displayRect.width).rounded())
        let height = Int(abs(displayRect.height).rounded())
        let dimensions = Set([width, height])
        guard dimensions == Set([720, 1280]) else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "AI 动态不是要求的 720p", context: ["width": String(width), "height": String(height)])
        }
        guard audioTracks.isEmpty else {
            throw AppError.safe("MEDIA_SPEC_INVALID", "AI 动态包含音轨，不符合静音要求")
        }
    }
}
