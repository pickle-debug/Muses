import SwiftUI
import UniformTypeIdentifiers

enum MTab: String, CaseIterable {
    case selection = "AI选品", products = "我的商品", publish = "快速发布", followUp = "销售跟进", settings = "个人设置"
    var icon: String {
        switch self {
        case .selection: "sparkles"
        case .products: "shippingbox"
        case .publish: "plus"
        case .followUp: "chart.line.uptrend.xyaxis"
        case .settings: "person.crop.circle"
        }
    }
}

struct MTabBar: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var keyboardVisible = false
    @Namespace private var selection
    @State private var isPressingPublish = false

    var body: some View {
        Group {
            if !keyboardVisible {
                ZStack(alignment: .top) {
                    barSurface
                        .padding(.top, 12)

                    // A real layout slot includes the raised area in hit testing.
                    // There is no selectable middle tab underneath this button.
                    publishButton
                        .accessibilitySortPriority(3)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
        .sensoryFeedback(.selection, trigger: app.selectedTab)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8), value: app.selectedTab)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    private var barSurface: some View {
        tabItems
            .background {
                Capsule()
                    .fill(reduceTransparency ? AnyShapeStyle(MusesTheme.surface) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
                    .shadow(color: MusesTheme.ink.opacity(0.09), radius: 18, y: 8)
            }
    }

    private var tabItems: some View {
        HStack(spacing: 0) {
            ForEach(Array(MTab.allCases.enumerated()), id: \.element) { index, tab in
                if tab == .publish {
                    // Layout only: no image, selection background or accessibility element.
                    Color.clear
                        .frame(width: 64, height: 52)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    tabButton(tab)
                        .accessibilitySortPriority(Double(5 - index))
                }
            }
        }
        .padding(6)
    }

    private var publishButton: some View {
        Button { app.selectTab(.publish) } label: {
            ZStack {
                publishSymbol
                    .background(MusesTheme.coral.gradient, in: Circle())
                    .shadow(color: MusesTheme.coral.opacity(isPressingPublish ? 0.42 : 0.18), radius: isPressingPublish ? 18 : 8, y: 4)
            }
            .scaleEffect(isPressingPublish ? 1.12 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.58), value: isPressingPublish)
        }
        .buttonStyle(FloatingTabPressStyle())
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in isPressingPublish = true }.onEnded { _ in isPressingPublish = false })
        .accessibilityLabel(MTab.publish.rawValue)
        .accessibilityIdentifier("workspace.tab.publish")
        .disabled(app.isWorking)
    }

    private var publishSymbol: some View {
        Image(systemName: "plus")
            .font(.system(size: 29, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .contentShape(Circle())
    }

    private func tabButton(_ tab: MTab) -> some View {
        let isSelected = app.selectedTab == tab
        return Button { app.selectTab(tab) } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .frame(height: 25)
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? MusesTheme.coral : MusesTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(MusesTheme.ink.opacity(0.07))
                        .matchedGeometryEffect(id: "selected-tab", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(FloatingTabPressStyle())
        .accessibilityLabel(tab.rawValue)
        .accessibilityIdentifier("workspace.tab.\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(app.isWorking)
    }
}

private struct FloatingTabPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct QuickPublishView: View {
    @EnvironmentObject private var app: AppModel
    let onChoosePhotos: () -> Void
    let onSmartRecognition: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    VStack(spacing: 10) {
                        publishOption("从相册选择", subtitle: "最多选择 \(AppModel.maximumSourcePhotoCount) 张商品图片", icon: "photo.on.rectangle.angled", prominent: true, action: onChoosePhotos)
                            .accessibilityIdentifier("workspace.publish.photos")
                        publishOption("智能识别", subtitle: "粘贴商品链接、文本，\n或上传文件进行识别", icon: "link", action: onSmartRecognition)
                            .accessibilityIdentifier("workspace.publish.smart")
                        publishOption("相机识别", subtitle: "拍摄商品图片", icon: "camera") {
                            app.alert = AppAlert(title: "相机识别暂未开放", message: "可以先创建商品，从相册添加已拍摄的商品图片。")
                        }
                        .accessibilityIdentifier("workspace.publish.camera")
                    }
                    Button { app.dismissQuickPublish() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(MusesTheme.ink.opacity(0.25), in: Circle())
                    }
                    .buttonStyle(FloatingTabPressStyle())
                    .padding(.top, 32)
                    .accessibilityLabel("关闭快速发布")
                    .accessibilityIdentifier("workspace.publish.close")
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 320)
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { app.dismissQuickPublish() }
                        .accessibilityHidden(true)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(MusesTheme.ink)
        .disabled(app.isWorking)
        .accessibilityAction(.escape) { app.dismissQuickPublish() }
    }

    private func publishOption(_ title: String, subtitle: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                    Text(subtitle).font(.subheadline)
                        .foregroundStyle(prominent ? .white.opacity(0.72) : MusesTheme.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                Image(systemName: icon).font(.system(size: 28, weight: .medium))
                    .frame(width: 34)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(prominent ? .white : MusesTheme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: prominent ? 110 : 88)
            .background(prominent ? MusesTheme.ink : .white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(FloatingTabPressStyle())
    }
}

struct SmartRecognitionView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showFileImporter = false
    @State private var uploadedFileName: String?
    @FocusState private var isInputFocused: Bool
    @ScaledMetric(relativeTo: .subheadline) private var inputHeight: CGFloat = 80

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Label("文本或链接识别", systemImage: "link")
                            .font(.headline.weight(.bold))
                        Spacer(minLength: 0)
                        Button {
                            isInputFocused = false
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("关闭智能识别")
                        .accessibilityIdentifier("workspace.publish.smart.close")
                    }
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("粘贴商品链接、笔记文本，或输入商品名称、卖点与规格。")
                                .foregroundStyle(MusesTheme.secondaryInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .focused($isInputFocused)
                            .frame(height: inputHeight)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("商品文本或链接")
                            .accessibilityIdentifier("workspace.publish.smart.input")
                    }
                    .font(.subheadline)
                    HStack(spacing: 8) {
                        Button {
                            isInputFocused = false
                            showFileImporter = true
                        } label: {
                            Label("上传文件", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("workspace.publish.smart.file")
                        Spacer(minLength: 0)
                        Button("开始识别") {
                            isInputFocused = false
                            app.alert = AppAlert(title: "文本识别暂未开放", message: "商品链接与自由文本识别尚未接入。你可以上传 CSV、TSV 或 JSON 文件导入 SKU。")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(text.trimmed.isEmpty ? Color.black.opacity(0.14) : MusesTheme.ink, in: Capsule())
                        .disabled(text.trimmed.isEmpty)
                        .accessibilityIdentifier("workspace.publish.smart.recognize")
                    }
                    if let uploadedFileName {
                        Text(uploadedFileName)
                            .font(.caption)
                            .foregroundStyle(MusesTheme.secondaryInk)
                            .lineLimit(2)
                    }
                    if app.isWorking {
                        ProgressView("正在导入 SKU…").font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(MusesTheme.ink, lineWidth: 2)
                }
                Button {
                    isInputFocused = false
                    app.alert = AppAlert(title: "截图识别暂未开放", message: "可以先创建商品，从相册添加含有商品信息的截图。")
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("截图识别", systemImage: "photo.badge.plus")
                            .font(.headline.weight(.bold))
                        Text("选择含有商品信息的页面截图")
                            .font(.subheadline)
                            .foregroundStyle(MusesTheme.secondaryInk)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .accessibilityIdentifier("workspace.publish.smart.screenshot")
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(.white)
        .foregroundStyle(MusesTheme.ink)
        .tint(MusesTheme.ink)
        .buttonStyle(.plain)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(app.isWorking)
        .task {
            // Wait for the sheet's entrance before requesting the keyboard.
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            isInputFocused = true
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .json, .commaSeparatedText, .tabSeparatedText]) { result in
            switch result {
            case .success(let url):
                uploadedFileName = url.lastPathComponent
                Task { await app.importSKUFile(url) }
            case .failure(let error):
                app.alert = AppAlert.from(error)
            }
        }
    }
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MusesLogo(compact: true).padding(.bottom, 8)
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(MusesTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProductSelectionView: View {
    @EnvironmentObject private var app: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                WorkspaceHeading(title: "AI选品", subtitle: "发现值得投入内容的商品。")
                ContentUnavailableView("选品分析即将开放", systemImage: "sparkle.magnifyingglass", description: Text("后续将在这里评估商品机会。现在可以先建立商品库，积累每个 SKU 的内容和销售数据。"))
                PrimaryButton(title: "先建立我的商品库", icon: "shippingbox") { app.selectTab(.products) }
            }.frame(maxWidth: 720).padding(20)
        }.musesPage()
    }
}
