import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProductInputView: View {
    @EnvironmentObject private var app: AppModel
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImageImporter = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(title: "录入 SKU", subtitle: "先保存商品资料，也可以补充图片后开始创作", step: "1 / 4  商品素材", backAction: { app.screen = .history })

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundStyle(MusesTheme.coral)
                                .frame(width: 46, height: 46)
                                .background(MusesTheme.coralSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("上传 3–6 张真实商品图").font(.headline)
                                Text("已选择 \(app.sourceAssets.count) 张").font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(app.sourceAssets) { asset in
                                ZStack(alignment: .topTrailing) {
                                    AssetImage(asset: asset)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Button { app.removeSource(asset) } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 34, height: 34)
                                            .foregroundStyle(MusesTheme.ink)
                                            .background(.white.opacity(0.92), in: Circle())
                                    }
                                    .accessibilityLabel("删除这张商品图")
                                    .padding(6)
                                }
                                .contextMenu {
                                    Button("向前移动", systemImage: "arrow.left") { app.moveSource(asset, by: -1) }
                                    Button("向后移动", systemImage: "arrow.right") { app.moveSource(asset, by: 1) }
                                    Button("删除", systemImage: "trash", role: .destructive) { app.removeSource(asset) }
                                }
                            }
                            if app.sourceAssets.count < 6 {
                                PhotosPicker(selection: $photoItems, maxSelectionCount: 6 - app.sourceAssets.count, matching: .images) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus").font(.title2)
                                        Text("添加图片").font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(MusesTheme.secondaryInk)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(MusesTheme.line, style: StrokeStyle(lineWidth: 1, dash: [6])) }
                                }
                            }
                        }
                    }
                }

                SurfaceCard {
                    VStack(spacing: 18) {
                        MusesTextField(title: "SKU 编号", icon: "number", placeholder: "例如：CUP-001", text: $app.sku)
                        Divider()
                        MusesTextField(title: "商品名称", icon: "tag", placeholder: "例如：透明波点玻璃杯", text: $app.productName)
                        Divider()
                        MusesTextField(title: "一句话真实卖点", icon: "sparkles", placeholder: "只写可核实的真实信息", text: $app.sellingPoint, axis: .vertical)
                    }
                }

                SecondaryButton(title: "从文件添加商品图", icon: "folder") { showImageImporter = true }
                    .disabled(app.sourceAssets.count >= 6 || isWorking)
                SecondaryButton(title: "保存 SKU 资料", icon: "square.and.arrow.down") { Task { await app.saveProductDraft() } }
                    .disabled(isWorking || app.sku.trimmed.isEmpty || app.productName.trimmed.isEmpty || app.sellingPoint.trimmed.isEmpty)

                if app.sourceAssets.count < 3 {
                    InfoBanner(text: app.connectionState == .preview ? "建议上传至少 3 个角度；预览模式选择 1 张即可继续。" : "还需上传 \(3 - app.sourceAssets.count) 张，真实生成要求至少 3 个角度。", kind: .warning)
                }
                if !app.sourceAssets.isEmpty {
                    InfoBanner(text: "点击“AI 识别商品”会向当前只读 Endpoint 发送 \(app.sourceAssets.count) 张所选商品图；请确认你有权上传。", kind: .neutral)
                }

                operationBanner

                PrimaryButton(
                    title: "AI 识别商品",
                    icon: "sparkles",
                    isLoading: isWorking,
                    disabled: app.sku.trimmed.isEmpty || app.productName.trimmed.isEmpty || app.sellingPoint.trimmed.isEmpty || app.sourceAssets.count < (app.connectionState == .preview ? 1 : 3)
                ) { Task { if await app.saveProductDraft(navigate: false) { await app.recognizeProduct() } } }
                Text("识别后仍需要你逐项确认")
                    .font(.caption)
                    .foregroundStyle(MusesTheme.secondaryInk)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: 680)
            .padding(20)
        }
        .musesPage()
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        do { try await app.addPhotoFile(url) }
                        catch { app.alert = AppAlert.from(error) }
                    }
                }
            case .failure(let error): app.alert = AppAlert.from(error)
            }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    await app.addPhoto(data: data, suggestedExtension: ext)
                }
                photoItems = []
            }
        }
    }

    private var isWorking: Bool { if case .working = app.operation { return true }; return false }
    @ViewBuilder private var operationBanner: some View {
        if case .failed(let message) = app.operation { InfoBanner(text: message, kind: .warning) }
    }
}

struct MusesTextField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(MusesTheme.coral)
                .frame(width: 42, height: 42)
                .background(MusesTheme.coralSoft, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(MusesTheme.secondaryInk)
                TextField(placeholder, text: $text, axis: axis)
                    .font(.body.weight(.medium))
                    .lineLimit(axis == .vertical ? 2...4 : 1...1)
            }
        }
    }
}

#if DEBUG
#Preview("Product Input") {
    MusesPreview.environment(.product) { ProductInputView() }
}
#endif
