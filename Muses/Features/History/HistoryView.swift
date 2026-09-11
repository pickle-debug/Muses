import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var filter: HistoryFilter = .all
    @State private var pendingDelete: Product?
    @State private var search = ""

    enum HistoryFilter: String, CaseIterable { case all = "全部", generating = "生成中", review = "待审核", saved = "已保存", failed = "失败" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    MusesLogo(compact: true)
                    Spacer()
                    Button { app.selectTab(.settings) } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44)
                            .foregroundStyle(MusesTheme.ink)
                            .background(.white.opacity(0.75), in: Circle())
                    }
                    .accessibilityLabel("设置 AI 服务")
                    Button { app.startNewProduct() } label: {
                        Label("新建", systemImage: "plus")
                            .fontWeight(.bold)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .foregroundStyle(.white)
                            .background(MusesTheme.coral, in: Capsule())
                    }
                }
                Text("我的商品")
                    .font(.system(size: 38, weight: .bold, design: .rounded))

                TextField("搜索商品名称或 SKU", text: $search)
                    .padding(14).background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HistoryFilter.allCases, id: \.self) { option in
                            Button(option.rawValue) { filter = option }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(filter == option ? .white : MusesTheme.ink)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 42)
                                .background(filter == option ? MusesTheme.coral : MusesTheme.surface, in: Capsule())
                        }
                    }
                }

                if filteredProducts.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            filter == .all ? "还没有商品" : "没有符合筛选的项目",
                            systemImage: filter == .all ? "sparkles" : "line.3.horizontal.decrease.circle",
                            description: Text(filter == .all ? "手动录入或从快速发布批量导入 SKU。" : "换一个状态筛选，或新建商品。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                    }
                    PrimaryButton(title: "新建商品", icon: "plus") { app.startNewProduct() }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredProducts) { product in
                            HistoryRow(product: product) {
                                app.showProduct(product)
                            } deleteAction: {
                                pendingDelete = product
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(20)
        }
        .musesPage()
        .confirmationDialog("删除本地项目？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除项目", role: .destructive) {
                guard let product = pendingDelete else { return }
                pendingDelete = nil
                Task { await app.delete(product: product) }
            }
        } message: {
            Text("本地商品素材、生成结果与任务记录将被删除。供应商已完成的调用和费用不会撤销。")
        }
    }

    private var filteredProducts: [Product] {
        app.snapshot.products.filter { product in
            search.trimmed.isEmpty || product.name.localizedCaseInsensitiveContains(search.trimmed) || (product.sku?.localizedCaseInsensitiveContains(search.trimmed) == true)
        }.filter { product in
            switch filter {
            case .all: true
            case .generating: latestCreation(for: product).map { [.generatingImage, .generatingVideo, .generatingCopy].contains($0.status) } == true
            case .review: latestCreation(for: product)?.status == .imageReview || latestCreation(for: product)?.status == .videoReview
            case .saved: product.status == .completed
            case .failed: product.status == .failed || latestCreation(for: product)?.status == .failed
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func latestCreation(for product: Product) -> Creation? {
        let snapshotIDs = Set(app.snapshot.productSnapshots.filter { $0.productID == product.id }.map(\.id))
        return app.snapshot.creations.filter { snapshotIDs.contains($0.productSnapshotID) }.max { $0.updatedAt < $1.updatedAt }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var app: AppModel
    let product: Product
    let action: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 16) {
                AssetImage(asset: thumbnail)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 9) {
                    Text(product.name).font(.headline).lineLimit(2)
                    Text("\(product.sku ?? "未设置 SKU") · \(app.creations(for: product.id).count) 个版本")
                        .font(.caption)
                        .foregroundStyle(MusesTheme.secondaryInk)
                    StatusPill(text: statusText, tone: statusTone)
                }
                Spacer(minLength: 6)
                VStack(spacing: 8) {
                    Menu {
                        Button("删除项目", role: .destructive, action: deleteAction)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    Button(action: action) {
                        Text("查看")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 42)
                            .background(MusesTheme.coralSoft, in: Capsule())
                    }
                }
            }
        }
    }

    private var thumbnail: LocalAsset? {
        guard let facts = app.snapshot.productSnapshots.first(where: { $0.id == product.currentSnapshotID }), let id = facts.sourceAssetIDs.first else { return nil }
        return app.snapshot.assets.first { $0.id == id }
    }
    private var statusText: String {
        if let creation = app.creations(for: product.id).last { return creation.status.displayName }
        return switch product.status { case .draft: "草稿"; case .factsPending: "待确认"; case .factsConfirmed: "已确认"; case .creating: "创作中"; case .completed: "已保存"; case .failed: "失败" }
    }
    private var statusTone: StatusPill.Tone {
        switch product.status { case .completed: .success; case .failed: .failure; case .factsPending: .warning; default: .neutral }
    }
}

#if DEBUG
#Preview("History") {
    MusesPreview.environment(.history) { HistoryView() }
}
#endif
