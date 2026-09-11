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
        // 切换特效版：取消下一行注释，并注释 originalPublishButton
         CometPublishButton(app: app)
//        originalPublishButton
    }

    private var originalPublishButton: some View {
        Button { app.selectTab(.publish) } label: {
            ZStack {
                if isPressingPublish && !reduceMotion {
                    Circle().stroke(MusesTheme.coral.opacity(0.35), lineWidth: 8)
                        .frame(width: 82, height: 82)
                        .scaleEffect(isPressingPublish ? 1.18 : 0.9)
                        .opacity(isPressingPublish ? 0.35 : 0)
                        .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: isPressingPublish)
                }
                publishSymbol
                    .background(MusesTheme.coral.gradient, in: Circle())
                    .shadow(color: MusesTheme.coral.opacity(isPressingPublish ? 0.42 : 0.18), radius: isPressingPublish ? 18 : 8, y: 4)
            }
        }
        .buttonStyle(FloatingTabPressStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.01).onChanged { _ in isPressingPublish = true }.onEnded { _ in isPressingPublish = false })
        .onChange(of: app.isQuickPublishPresented) { _, presented in if !presented { isPressingPublish = false } }
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
    @State private var showImporter = false
    @State private var showVoiceHint = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "快速发布", subtitle: "从一个 SKU 开始，把商品变成种草内容。")
                VStack(alignment: .leading, spacing: 18) {
                    Label("小红书图文工作台", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                    Text("好商品，\n值得被看见。")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("录入商品 · 生成图文 · 逐版优化 · 跟进转化")
                        .font(.subheadline).foregroundStyle(MusesTheme.secondaryInk)
                    Text("告诉我你要发布什么，Muses 会帮你整理成 SKU。")
                        .font(.subheadline.weight(.medium)).foregroundStyle(MusesTheme.ink)
                    Button { app.startNewProduct(); showVoiceHint = true } label: {
                        Label("按住说，松开生成", systemImage: "waveform")
                            .font(.headline.weight(.bold)).frame(maxWidth: .infinity).frame(minHeight: 56)
                            .foregroundStyle(.white).background(MusesTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }.buttonStyle(.plain)
                    HStack(spacing: 10) {
                        publishOption("相册识别", icon: "photo.on.rectangle.angled") { app.startNewProduct() }
                        publishOption("导入表格", icon: "tablecells") { showImporter = true }
                    }
                    if showVoiceHint { Text("已进入录入页，可以直接说出商品名、卖点和规格。") .font(.caption).foregroundStyle(MusesTheme.secondaryInk) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MusesTheme.coralSoft.gradient, in: RoundedRectangle(cornerRadius: 28))
                Text("支持 CSV、TSV、JSON，最多 500 个 SKU。导入名称和卖点后，可逐个补充商品图。")
                    .font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                DisclosureGroup("查看文件格式") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CSV / TSV 必填表头：SKU、商品名称、卖点")
                        Text("SKU,商品名称,卖点\nCUP-001,透明玻璃杯,杯身有刻度")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("JSON 字段：sku、name、sellingPoint。Excel 请导出为 UTF-8 CSV。")
                    }
                    .font(.caption).padding(.top, 10)
                }
                HStack {
                    Text("最近商品").font(.title3.bold())
                    Spacer()
                    Button("查看全部") { app.selectTab(.products) }.font(.subheadline)
                }
                if app.snapshot.products.isEmpty {
                    ContentUnavailableView("等待你的第一个商品", systemImage: "shippingbox", description: Text("无需配置 API Key，即可录入和管理 SKU。"))
                } else {
                    ForEach(Array(app.snapshot.products.sorted { $0.createdAt > $1.createdAt }.prefix(6))) { product in
                        SKUListRow(product: product)
                    }
                }
            }
            .frame(maxWidth: 720).padding(20)
        }
        .musesPage()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .json, .plainText]) { result in
            switch result {
            case .success(let url): Task { await app.importSKUFile(url) }
            case .failure(let error): app.alert = AppAlert.from(error)
            }
        }
        .disabled(app.isWorking)
    }

    private func publishOption(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 48).foregroundStyle(MusesTheme.ink).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 15)).overlay { RoundedRectangle(cornerRadius: 15).stroke(MusesTheme.line, lineWidth: 1) } }.buttonStyle(.plain)
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

struct SKUListRow: View {
    @EnvironmentObject private var app: AppModel
    let product: Product
    var body: some View {
        Button { app.showProduct(product) } label: {
            HStack(spacing: 14) {
                AssetImage(asset: thumbnail).frame(width: 64, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name).font(.headline).lineLimit(2)
                    Text(product.sku ?? "未设置 SKU").font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                    Text("\(app.creations(for: product.id).count) 个内容版本").font(.caption).foregroundStyle(MusesTheme.coral)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(MusesTheme.secondaryInk)
            }
            .padding(16)
            .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(app.isWorking)
    }
    private var thumbnail: LocalAsset? {
        let id = app.snapshot.productSnapshots.first { $0.id == product.currentSnapshotID }?.sourceAssetIDs.first
        return app.snapshot.assets.first { $0.id == id }
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

struct SKUDetailView: View {
    @EnvironmentObject private var app: AppModel
    let productID: MusesID
    @State private var trackingCreation: Creation?
    private var product: Product? { app.snapshot.products.first { $0.id == productID } }
    var body: some View {
        ScrollView {
            if let product {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: product.name, subtitle: product.sku ?? "未设置 SKU", backAction: { app.screen = .history })
                    let facts = app.snapshot.productSnapshots.first { $0.id == product.currentSnapshotID }
                    if let assetID = facts?.sourceAssetIDs.first {
                        AssetImage(asset: app.snapshot.assets.first { $0.id == assetID })
                            .frame(height: 210).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    Text(facts?.verifiedSellingPoints.joined(separator: "；") ?? "待补充商品资料")
                        .foregroundStyle(MusesTheme.secondaryInk)
                    let versions = app.creations(for: productID)
                    let unfinished = versions.last { ![.ready, .saved].contains($0.status) }
                    PrimaryButton(title: unfinished != nil ? "继续当前版本" : versions.isEmpty ? "开始生成 V1" : "升级到下一版本", icon: "sparkles") {
                        Task { await app.prepareNextVersion(for: product) }
                    }
                    if versions.isEmpty {
                        SecondaryButton(title: "编辑资料与商品图", icon: "pencil") { Task { await app.resume(product: product) } }
                    }
                    Text("内容版本").font(.title3.bold())
                    if versions.isEmpty {
                        ContentUnavailableView("还没有图文版本", systemImage: "square.stack", description: Text("补充商品图并确认信息后，开始生成第一版。"))
                    }
                    ForEach(versions.reversed()) { creation in
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(app.versionLabel(creation)).font(.title2.bold())
                                    if creation.isPreview == true { StatusPill(text: "预览", tone: .warning) }
                                    Spacer()
                                    StatusPill(text: creation.status.displayName, tone: .neutral)
                                }
                                Text(creation.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                                if let note = creation.revisionNote { Text(note).font(.subheadline) }
                                if let copy = app.snapshot.copyPackages.first(where: { $0.creationID == creation.id }), copy.titles.indices.contains(copy.selectedTitleIndex) {
                                    Text(copy.titles[copy.selectedTitleIndex]).font(.headline)
                                    Text(copy.body).font(.subheadline).lineLimit(3).foregroundStyle(MusesTheme.secondaryInk)
                                }
                                if let metrics = creation.tracking?.samples.last { MetricsSummary(metrics: metrics) }
                                HStack(spacing: 10) {
                                    SecondaryButton(title: "查看内容", icon: "doc.text.image") {
                                        Task { await app.resume(product: product, creation: creation) }
                                    }
                                    if [.ready, .saved].contains(creation.status), creation.isPreview != true {
                                        SecondaryButton(title: creation.tracking == nil ? "登记帖子" : "更新数据", icon: "chart.bar") { trackingCreation = creation }
                                    }
                                }
                            }
                        }
                    }
                }.frame(maxWidth: 720).padding(20)
            }
        }
        .musesPage()
        .disabled(app.isWorking)
        .sheet(item: $trackingCreation) { creation in PostTrackingSheet(creationID: creation.id) }
    }
}

extension CreationStatus {
    var displayName: String {
        switch self {
        case .draft: "草稿"
        case .generatingImage: "图片生成中"
        case .imageReview: "待审核图片"
        case .generatingVideo: "动态生成中"
        case .videoReview: "待审核动态"
        case .generatingCopy: "文案生成中"
        case .ready: "待发布"
        case .saved: "已保存素材"
        case .failed: "生成失败"
        }
    }
}
