import AVKit
import SwiftUI
import UIKit

struct LocalImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    LinearGradient(colors: [MusesTheme.coralSoft, MusesTheme.greenSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(MusesTheme.secondaryInk.opacity(0.45))
                }
            }
        }
    }
}

struct AssetImage: View {
    @EnvironmentObject private var app: AppModel
    let asset: LocalAsset?
    var contentMode: ContentMode = .fill
    @State private var url: URL?

    var body: some View {
        LocalImageView(url: url, contentMode: contentMode)
            .task(id: asset?.id) { url = await app.url(for: asset) }
    }
}

struct ProductMediaHero: View {
    @EnvironmentObject private var app: AppModel
    let asset: LocalAsset?
    var height: CGFloat = 430

    var body: some View {
        AssetImage(asset: asset, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topTrailing) {
                StatusPill(text: app.connectionState == .demo ? "演示预览" : "3:4 生成结果", tone: app.connectionState == .demo ? .warning : .success)
                    .padding(14)
            }
            .accessibilityLabel(app.connectionState == .demo ? "演示商品预览" : "生成商品图片")
    }
}

struct GeneratedVideoView: View {
    @EnvironmentObject private var app: AppModel
    let asset: LocalAsset?
    @State private var url: URL?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                AssetImage(asset: app.generatedImageAsset, contentMode: .fit)
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 62))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Text(app.connectionState == .demo ? "演示模式无真实视频" : "正在加载视频")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.5), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task(id: asset?.id) {
            url = await app.url(for: asset)
            if let url { player = AVPlayer(url: url) }
        }
    }
}

struct LoadingStageView: View {
    let title: String
    let subtitle: String
    var steps: [String]
    var currentStep = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        SurfaceCard {
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(MusesTheme.greenSoft)
                        .frame(width: 116, height: 116)
                        .scaleEffect(pulsing ? 1.07 : 0.92)
                        .opacity(pulsing ? 0.72 : 1)
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(MusesTheme.green)
                }
                VStack(spacing: 8) {
                    Text(title).font(.title3.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(MusesTheme.secondaryInk).multilineTextAlignment(.center)
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack(spacing: 8) {
                            Image(systemName: index < currentStep ? "checkmark.circle.fill" : index == currentStep ? "circle.dotted.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(index <= currentStep ? MusesTheme.green : MusesTheme.line)
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(index <= currentStep ? MusesTheme.ink : MusesTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("第 \(index + 1) 步，\(step)，\(index < currentStep ? "已完成" : index == currentStep ? "进行中" : "未开始")")
                    }
                }
                ProgressView().tint(MusesTheme.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

struct ReviewChecklist: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("商品一致性检查")
                    .font(.title3.weight(.bold))
                    .padding(.bottom, 8)
                ForEach(items, id: \.self) { item in
                    Button {
                        if selected.contains(item) { selected.remove(item) } else { selected.insert(item) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(item) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(item) ? MusesTheme.green : MusesTheme.secondaryInk.opacity(0.45))
                            Text(item)
                                .foregroundStyle(MusesTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(selected.contains(item) ? "已确认" : "待确认")
                                .font(.caption)
                                .foregroundStyle(selected.contains(item) ? MusesTheme.green : MusesTheme.secondaryInk)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item != items.last { Divider().foregroundStyle(MusesTheme.line) }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Media States") {
    MusesPreview.environment(.imageReview) {
        ScrollView {
            VStack(spacing: 16) {
                ProductMediaHero(asset: MusesPreview.model(for: .imageReview).generatedImageAsset, height: 320)
                LoadingStageView(title: "正在生成", subtitle: "展示异步任务等待状态", steps: ["准备", "生成", "审核"], currentStep: 1)
                ReviewChecklist(items: ["外形一致", "颜色一致"], selected: .constant(["外形一致"]))
            }
            .padding(20)
        }
        .musesPage()
    }
}
#endif
