import SwiftUI

struct ImageGenerationView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(title: "AI 创作", subtitle: "正在生成一张生活方式种草图", step: "3 / 4  AI 创作", backAction: { app.screen = .history })
                SurfaceCard {
                    HStack(spacing: 16) {
                        AssetImage(asset: app.sourceAssets.first)
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("参考商品").font(.caption.weight(.bold)).foregroundStyle(MusesTheme.secondaryInk)
                            Text(app.productName).font(.headline)
                            StatusPill(text: "商品事实已确认", tone: .success)
                        }
                        Spacer()
                    }
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("固定创作设置").font(.headline)
                        SummaryRow(icon: "square.text.square", title: "平台", value: "小红书")
                        SummaryRow(icon: "person.crop.rectangle", title: "场景", value: "真人手持生活方式")
                        SummaryRow(icon: "rectangle.portrait", title: "画幅", value: "3:4")
                        SummaryRow(icon: "square.stack.3d.up", title: "数量", value: "1 张")
                        SummaryRow(icon: "shippingbox", title: "模型", value: app.imageModelName)
                    }
                }
                LoadingStageView(title: operationText, subtitle: "只显示真实供应商状态与已等待过程，不提供虚假倒计时。", steps: ["读取商品事实", "生成生活画面", "等待人工审核"], currentStep: 1)
                if case .working = app.operation {
                    SecondaryButton(title: "取消本机等待", icon: "xmark.circle", destructive: true) { Task { await app.cancelCurrentGeneration() } }
                }
                if case .failed(let message) = app.operation {
                    InfoBanner(text: message, kind: .warning)
                    if app.canRetryImageDownload {
                        PrimaryButton(title: "继续下载原图片", icon: "arrow.down.circle") { Task { await app.retryImageDownload() } }
                    } else if app.isImageSubmissionUnknown {
                        PrimaryButton(title: "用原幂等键重试（需供应商支持）", icon: "arrow.clockwise") { Task { await app.retryUnknownImageSubmission() } }
                    } else if app.canCreateReplacementImageJob {
                        PrimaryButton(title: "创建新图片任务", icon: "arrow.clockwise") { Task { await app.retryFailedImageGeneration() } }
                    }
                }
            }
            .frame(maxWidth: 700)
            .padding(20)
        }
        .musesPage()
    }

    private var operationText: String {
        if case .working(let text) = app.operation { return text }
        if case .failed = app.operation { return "图片生成未完成" }
        return "正在准备"
    }
}

struct VideoGenerationView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(title: "生成 AI 动态", subtitle: app.videoSummary, backAction: { app.screen = .history })
                ProductMediaHero(asset: app.generatedImageAsset, height: 360)
                InfoBanner(text: "高成本操作已由你明确触发。离开页面后任务 ID 会保存在本机；回到前台只继续查询，不重复提交。", kind: .neutral)
                LoadingStageView(title: operationText, subtitle: "轻微自然动作与镜头运动，商品本体不得形变或新增文字。", steps: ["提交动态任务", "供应商生成", "下载到本机"], currentStep: 1)
                if case .working = app.operation {
                    SecondaryButton(title: "停止查询", icon: "pause.circle", destructive: true) { Task { await app.cancelCurrentGeneration() } }
                }
                if case .failed(let message) = app.operation {
                    InfoBanner(text: message, kind: .warning)
                    if app.isVideoSubmissionUnknown {
                        PrimaryButton(title: "用原幂等键重试（需供应商支持）", icon: "arrow.clockwise") { Task { await app.retryUnknownVideoSubmission() } }
                    } else {
                        if app.canRetryVideoDownload {
                            PrimaryButton(title: "继续下载原动态", icon: "arrow.down.circle") { Task { await app.retryVideoDownload() } }
                        } else if app.canResumeVideoJob {
                            PrimaryButton(title: "继续查询原任务", icon: "arrow.clockwise") { app.handleSceneBecameActive() }
                        }
                        if app.canCreateReplacementVideoJob {
                            SecondaryButton(title: "远端已失败，创建新动态任务", icon: "plus", destructive: true) { Task { await app.retryFailedVideoGeneration() } }
                        }
                    }
                }
            }
            .frame(maxWidth: 700)
            .padding(20)
        }
        .musesPage()
    }

    private var operationText: String {
        if case .working(let text) = app.operation { return text }
        if case .failed = app.operation { return "动态任务需要处理" }
        return "正在创建动态"
    }
}

private struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(MusesTheme.coral).frame(width: 26)
            Text(title).foregroundStyle(MusesTheme.secondaryInk)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 38)
    }
}

#if DEBUG
#Preview("Image Generation") {
    MusesPreview.environment(.imageGeneration) { ImageGenerationView() }
}

#Preview("Video Generation") {
    MusesPreview.environment(.videoGeneration) { VideoGenerationView() }
}
#endif
