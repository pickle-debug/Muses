import ImageIO
import SwiftUI
import UIKit

struct LocalImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: ImageThumbnail?
    @State private var completedRequest: ThumbnailRequest?

    var body: some View {
        GeometryReader { geometry in
            let pixels = max(geometry.size.width, geometry.size.height) * displayScale
            let request = ThumbnailRequest(url: url, maximumPixels: Int(min(2048, max(128, ceil(pixels / 128) * 128))))
            ZStack {
                Color.white.opacity(0.45)
                if url == nil {
                    ImagePlaceholder(state: .empty)
                } else if completedRequest != request {
                    ImagePlaceholder(state: .loading)
                } else if let thumbnail {
                    Image(decorative: thumbnail.image, scale: displayScale, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ImagePlaceholder(state: .failed)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: request) {
                guard completedRequest != request else { return }
                thumbnail = nil
                completedRequest = nil
                guard let url = request.url else { return }
                let task = Task.detached(priority: .userInitiated) {
                    ImageThumbnail.load(url: url, maximumPixels: request.maximumPixels)
                }
                let result = await withTaskCancellationHandler {
                    await task.value
                } onCancel: {
                    task.cancel()
                }
                guard !Task.isCancelled else { return }
                thumbnail = result
                completedRequest = request
            }
        }
    }
}

private struct ThumbnailRequest: Hashable, Sendable {
    let url: URL?
    let maximumPixels: Int
}

// CGImage is immutable; decoding stays off the main actor and only its result crosses back.
private struct ImageThumbnail: @unchecked Sendable {
    let image: CGImage

    nonisolated static func load(url: URL, maximumPixels: Int) -> ImageThumbnail? {
        autoreleasepool {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixels
                  ] as CFDictionary),
                  !Task.isCancelled else { return nil }
            return ImageThumbnail(image: image)
        }
    }
}

private struct ImagePlaceholder: View {
    enum State { case empty, loading, failed }
    let state: State

    var body: some View {
        ZStack {
            Color.white.opacity(0.45)
            switch state {
            case .loading:
                ProgressView().tint(MusesTheme.secondaryInk)
                    .accessibilityLabel("正在加载图片")
            case .empty:
                Image(systemName: "photo")
                    .font(.title2).foregroundStyle(MusesTheme.secondaryInk)
                    .accessibilityLabel("暂无图片")
            case .failed:
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle").font(.title2)
                    Text("无法读取").font(.caption2)
                }
                .foregroundStyle(MusesTheme.secondaryInk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("图片加载失败，请重新添加")
            }
        }
    }
}

struct AssetImage: View {
    let asset: LocalAsset?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let asset {
            ResolvedAssetImage(asset: asset, contentMode: contentMode)
                .id(asset.id)
        } else {
            ImagePlaceholder(state: .empty)
        }
    }
}

private struct ResolvedAssetImage: View {
    @EnvironmentObject private var app: AppModel
    let asset: LocalAsset
    let contentMode: ContentMode
    @State private var url: URL?
    @State private var isResolving = true

    var body: some View {
        Group {
            if let url {
                LocalImageView(url: url, contentMode: contentMode)
            } else {
                ImagePlaceholder(state: isResolving ? .loading : .failed)
            }
        }
        .task(id: asset.id) {
            let resolvedURL = await app.url(for: asset)
            guard !Task.isCancelled else { return }
            url = resolvedURL
            isResolving = false
        }
    }
}
