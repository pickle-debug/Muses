import SwiftUI

struct CopyResultView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "文案结果", subtitle: "选择标题、修改正文并删除不需要的话题", step: "4 / 4  文案", backAction: { app.screen = .videoReview })
                InfoBanner(text: "AI 内容，请核对商品事实。禁止虚构经历、价格、疗效、权威背书或未经确认的评价。", kind: .warning)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择标题").font(.title3.weight(.bold))
                        ForEach(app.copyTitles.indices, id: \.self) { index in
                            Button { app.selectedTitleIndex = index } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: app.selectedTitleIndex == index ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(app.selectedTitleIndex == index ? MusesTheme.coral : MusesTheme.secondaryInk.opacity(0.5))
                                    Text(app.copyTitles[index])
                                        .foregroundStyle(MusesTheme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(14)
                                .background(app.selectedTitleIndex == index ? MusesTheme.coralSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 15))
                                .overlay { RoundedRectangle(cornerRadius: 15).stroke(app.selectedTitleIndex == index ? MusesTheme.coral.opacity(0.55) : MusesTheme.line) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("正文内容").font(.title3.weight(.bold)); Spacer(); Image(systemName: "pencil") }
                        TextEditor(text: $app.copyBody)
                            .frame(minHeight: 210)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("话题标签").font(.title3.weight(.bold))
                        FlowLayout(spacing: 8) {
                            ForEach(app.copyTopics, id: \.self) { topic in
                                Button {
                                    app.copyTopics.removeAll { $0 == topic }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text("#\(topic.replacingOccurrences(of: "#", with: ""))")
                                        Image(systemName: "xmark.circle.fill").font(.caption)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.13))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 9)
                                    .background(MusesTheme.greenSoft, in: Capsule())
                                }
                                .accessibilityLabel("删除话题 \(topic)")
                            }
                        }
                    }
                }

                if case .failed(let message) = app.operation { InfoBanner(text: message, kind: .warning) }
                PrimaryButton(title: "确认内容", icon: "checkmark", disabled: app.copyTitles.isEmpty || app.copyBody.trimmed.isEmpty || app.copyTopics.isEmpty) {
                    Task { await app.confirmCopy() }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 720)
            .padding(20)
        }
        .musesPage()
    }
}

struct SaveResultView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(title: "保存与发布", subtitle: "作品已完成，可保存到相册后人工发布", backAction: { app.screen = .copyResult })
                ProductMediaHero(asset: app.generatedImageAsset, height: 390)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("保存到相册").font(.title3.weight(.bold))
                            Spacer()
                            if savedMediaCount > 0 { StatusPill(text: "已保存 \(savedMediaCount) 项", tone: .success) }
                        }
                        HStack(spacing: 10) {
                            ExportItem(icon: "livephoto", title: "Live Photo", subtitle: "iPhone 实况", status: app.exportRecord?.livePhotoStatus ?? .notRequested)
                            ExportItem(icon: "play.rectangle", title: "MP4", subtitle: "通用保底", status: app.exportRecord?.videoStatus ?? .notRequested)
                            ExportItem(icon: "photo", title: "静态图", subtitle: "3:4 原图", status: app.exportRecord?.imageStatus ?? .notRequested)
                        }
                        if app.connectionState == .demo {
                            InfoBanner(text: "演示模式没有真实生成媒体，因此不会向系统相册写入文件。", kind: .warning)
                        }
                        PrimaryButton(title: "保存 3 项媒体", icon: "square.and.arrow.down", isLoading: isWorking, disabled: !app.hasRealGeneratedMedia) {
                            Task { await app.saveAllMedia() }
                        }
                        if hasSaveFailure {
                            SecondaryButton(title: "打开系统设置", icon: "gear") { Task { await app.openSystemSettings() } }
                        }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(MusesTheme.coral)
                                .frame(width: 48, height: 48)
                                .background(MusesTheme.coralSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("发布到小红书").font(.headline)
                                Text("先复制文案，再打开小红书人工发布").font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                            }
                        }
                        HStack(spacing: 10) {
                            SecondaryButton(title: app.exportRecord?.copyStatus == .saved ? "已复制" : "复制文案", icon: "doc.on.doc") { Task { await app.copyTextToClipboard() } }
                            PrimaryButton(title: "打开小红书", icon: "arrow.up.forward.app") { Task { await app.openXiaohongshu() } }
                        }
                    }
                }

                InfoBanner(text: "发布前请再次核对商品事实与平台规范；保存记录不代表已经发布。", kind: .neutral)
                SecondaryButton(title: "返回创作记录", icon: "clock.arrow.circlepath") { app.screen = .history }
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: 720)
            .padding(20)
        }
        .musesPage()
    }

    private var isWorking: Bool { if case .working = app.operation { return true }; return false }
    private var savedMediaCount: Int {
        [app.exportRecord?.livePhotoStatus, app.exportRecord?.videoStatus, app.exportRecord?.imageStatus].compactMap { $0 }.filter { $0 == .saved }.count
    }
    private var hasSaveFailure: Bool {
        [app.exportRecord?.livePhotoStatus, app.exportRecord?.videoStatus, app.exportRecord?.imageStatus].contains(.failed)
    }
}

private struct ExportItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: ExportItemStatus

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).frame(width: 44, height: 44).background(.white, in: Circle())
            Text(title).font(.caption.weight(.bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.caption2).foregroundStyle(MusesTheme.secondaryInk).multilineTextAlignment(.center)
            statusView
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(MusesTheme.background.opacity(0.74), in: RoundedRectangle(cornerRadius: 17))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .notRequested: Text("未保存").foregroundStyle(MusesTheme.secondaryInk)
        case .saving: ProgressView()
        case .saved: Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(MusesTheme.green)
        case .failed: Label("失败", systemImage: "exclamationmark.circle.fill").foregroundStyle(MusesTheme.coral)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Copy Result") {
    MusesPreview.environment(.copyResult) { CopyResultView() }
}

#Preview("Save Result") {
    MusesPreview.environment(.saveResult) { SaveResultView() }
}
#endif
