import SwiftUI

struct ImageReviewView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showIssues = false
    @State private var issues: Set<ReviewIssue> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "审核种草图", subtitle: "请确认 AI 没有改动真实商品", backAction: { app.screen = .history })
                if app.connectionState == .demo { InfoBanner(text: "演示模式沿用你上传的参考图展示审核交互，不代表图片已由 AI 生成。", kind: .warning) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(app.sourceAssets) { asset in
                            AssetImage(asset: asset)
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 14).stroke(MusesTheme.line) }
                                .accessibilityLabel("商品参考图")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProductMediaHero(asset: app.generatedImageAsset)
                ReviewChecklist(items: app.imageReviewItems, selected: $app.selectedImageChecks)
                InfoBanner(text: "这是人工审核门。所有项目由你确认后，才允许进入 AI 动态生成。", kind: .neutral)
                VStack(spacing: 12) {
                    PrimaryButton(title: "商品一致，可以继续", icon: "checkmark.circle", disabled: !app.imageReviewComplete) {
                        Task { await app.approveImageAndGenerateVideo() }
                    }
                    SecondaryButton(title: "有问题，重新生成", icon: "arrow.clockwise", destructive: true) { showIssues = true }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 720)
            .padding(20)
        }
        .musesPage()
        .sheet(isPresented: $showIssues) {
            IssueSelectionSheet(title: "指出图片问题", issues: [.shapeChanged, .wrongColor, .wrongPattern, .wrongText, .wrongMaterial, .addedObject, .other], selected: $issues) {
                showIssues = false
                Task { await app.rejectImage(issues: Array(issues)) }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct VideoReviewView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showIssues = false
    @State private var issues: Set<ReviewIssue> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "审核 AI 动态", subtitle: "检查动态效果，确认无误后通过", backAction: { app.screen = .history })
                GeneratedVideoView(asset: app.generatedVideoAsset)
                StatusPill(text: "\(app.videoSummary) · 动态生成完成", tone: .success)
                ReviewChecklist(items: app.videoReviewItems, selected: $app.selectedVideoChecks)
                InfoBanner(text: "保存时会同时保留通用 MP4。Demo 不提供 Android 动态照片入口。", kind: .neutral)
                if case .failed(let message) = app.operation {
                    InfoBanner(text: message, kind: .warning)
                    PrimaryButton(title: "只重试文案生成", icon: "text.badge.plus") { Task { await app.retryCopyGeneration() } }
                }
                VStack(spacing: 12) {
                    PrimaryButton(title: "动态通过", icon: "checkmark.circle", disabled: !app.videoReviewComplete) {
                        Task { await app.approveVideoAndGenerateCopy() }
                    }
                    SecondaryButton(title: "只重新生成动态", icon: "arrow.clockwise", destructive: true) { showIssues = true }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 720)
            .padding(20)
        }
        .musesPage()
        .sheet(isPresented: $showIssues) {
            IssueSelectionSheet(title: "指出动态问题", issues: [.deformation, .abnormalContact, .backgroundJump, .shapeChanged, .wrongColor, .wrongPattern, .other], selected: $issues) {
                showIssues = false
                Task { await app.rejectVideo(issues: Array(issues)) }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct IssueSelectionSheet: View {
    let title: String
    let issues: [ReviewIssue]
    @Binding var selected: Set<ReviewIssue>
    let submit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(issues, id: \.self) { issue in
                Button {
                    if selected.contains(issue) { selected.remove(issue) } else { selected.insert(issue) }
                } label: {
                    HStack {
                        Text(issue.label).foregroundStyle(MusesTheme.ink)
                        Spacer()
                        Image(systemName: selected.contains(issue) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(issue) ? MusesTheme.coral : MusesTheme.secondaryInk)
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("带入返修", action: submit).disabled(selected.isEmpty) }
            }
        }
    }
}

#if DEBUG
#Preview("Image Review") {
    MusesPreview.environment(.imageReview) { ImageReviewView() }
}

#Preview("Image Review Issues") {
    IssueSelectionSheet(
        title: "指出图片问题",
        issues: [.shapeChanged, .wrongColor, .wrongPattern, .wrongText, .other],
        selected: .constant([.wrongColor]),
        submit: {}
    )
}

#Preview("Video Review Issues") {
    IssueSelectionSheet(
        title: "指出动态问题",
        issues: [.deformation, .abnormalContact, .backgroundJump, .other],
        selected: .constant([.deformation]),
        submit: {}
    )
}

#Preview("Video Review") {
    MusesPreview.environment(.videoReview) { VideoReviewView() }
}
#endif
