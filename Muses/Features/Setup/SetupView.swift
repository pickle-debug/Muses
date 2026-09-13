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
                    Text("个人设置")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("管理 AI 服务与本机偏好")
                        .font(.title3)
                        .foregroundStyle(MusesTheme.secondaryInk)
                }
                .padding(.top, 34)

                InfoBanner(text: "商品创建和查看无需 API Key。", kind: .neutral)

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
                            InfoBanner(text: "服务配置尚未填写，不影响商品创建和查看。", kind: .neutral)
                        }

                        PrimaryButton(title: "完成设置", icon: "checkmark") { app.selectTab(.products) }
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
            Text("删除后需要重新输入 Key 才能连接服务，现有本地商品不会删除。")
        }
    }

    private var keyPlaceholder: String {
        app.hasStoredCredential ? "已保存；如需替换请输入新 Key" : "输入单独发放的临时 Key"
    }

    @ViewBuilder private var connectionStatus: some View {
        switch app.connectionState {
        case .idle: EmptyView()
        case .testing: HStack { ProgressView(); Text("正在测试低成本连接…") }.foregroundStyle(MusesTheme.secondaryInk)
        case .connected: InfoBanner(text: "服务连接成功。")
        case .preview: EmptyView()
        case .failed(let message): InfoBanner(text: message, kind: .warning)
        }
    }
}

#if DEBUG
#Preview("Setup") {
    MusesPreview.environment(.setup) { SetupView() }
}
#endif
