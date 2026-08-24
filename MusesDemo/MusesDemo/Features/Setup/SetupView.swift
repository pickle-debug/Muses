import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showKey = false
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    MusesLogo()
                    Text("开始使用 Muses")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("连接你的 AI 服务")
                        .font(.title3)
                        .foregroundStyle(MusesTheme.secondaryInk)
                }
                .padding(.top, 34)

                InfoBanner(text: "本次测试会将你选择的商品素材发送到开发者配置的生成服务。请仅上传你有权使用的素材。", kind: .warning)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundStyle(MusesTheme.green)
                                .frame(width: 52, height: 52)
                                .background(MusesTheme.greenSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("服务地址").font(.headline)
                                Text(app.endpointDisplay)
                                    .font(.caption)
                                    .foregroundStyle(MusesTheme.secondaryInk)
                                    .lineLimit(2)
                            }
                            Spacer()
                            StatusPill(text: "只读", tone: .neutral)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 9) {
                            Text("临时 API Key").font(.headline)
                            HStack {
                                Group {
                                    if showKey { TextField(keyPlaceholder, text: $app.apiKey) }
                                    else { SecureField(keyPlaceholder, text: $app.apiKey) }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                Button {
                                    guard !app.hasStoredCredential || !app.apiKey.trimmed.isEmpty else { return }
                                    showKey.toggle()
                                } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(showKey ? "隐藏 Key" : "显示正在输入的 Key")
                                .disabled(app.hasStoredCredential && app.apiKey.trimmed.isEmpty)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(MusesTheme.line) }
                            Text("仅保存在本机；保存后不提供复制回剪贴板。")
                                .font(.caption)
                                .foregroundStyle(MusesTheme.secondaryInk)
                        }

                        connectionStatus

                        SecondaryButton(title: app.hasStoredCredential && app.apiKey.trimmed.isEmpty ? "重新测试已保存 Key" : "测试连接", icon: "network") {
                            Task { await app.testConnection() }
                        }
                        .disabled(app.connectionState == .testing || (!app.hasStoredCredential && app.apiKey.trimmed.isEmpty) || app.isPlaceholderConfiguration)

                        if app.isPlaceholderConfiguration {
                            InfoBanner(text: "真实供应商配置尚未填写。可先进入演示模式体验完整 UI 和审核流程；演示模式不会调用模型或保存示例媒体。", kind: .neutral)
                            SecondaryButton(title: "进入安全演示模式", icon: "play.rectangle") { app.enterDemoMode() }
                        }

                        PrimaryButton(
                            title: app.connectionState == .demo ? "进入演示" : "保存并继续",
                            icon: "arrow.right",
                            disabled: app.connectionState != .connected && app.connectionState != .demo
                        ) { app.saveSetupAndContinue() }
                    }
                }

                if app.hasStoredCredential {
                    Button("删除本地 Key", role: .destructive) { showDelete = true }
                        .foregroundStyle(MusesTheme.secondaryInk)
                        .padding(.bottom, 28)
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)
        }
        .musesPage()
        .confirmationDialog("删除本地 Key？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { app.deleteCredential() }
        } message: {
            Text("删除后需要重新输入临时 Key 才能继续真实创作，现有本地项目不会删除。")
        }
    }

    private var keyPlaceholder: String {
        app.hasStoredCredential ? "已保存；如需替换请输入新 Key" : "输入单独发放的临时 Key"
    }

    @ViewBuilder private var connectionStatus: some View {
        switch app.connectionState {
        case .idle: EmptyView()
        case .testing: HStack { ProgressView(); Text("正在测试低成本连接…") }.foregroundStyle(MusesTheme.secondaryInk)
        case .connected: InfoBanner(text: "连接成功，可以开始创建商品内容。")
        case .demo: InfoBanner(text: "演示模式已开启：只模拟状态转换，不发起真实生成。", kind: .warning)
        case .failed(let message): InfoBanner(text: message, kind: .warning)
        }
    }
}

#if DEBUG
#Preview("Setup") {
    MusesPreview.environment(.setup) { SetupView() }
}
#endif
