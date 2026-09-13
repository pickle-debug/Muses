import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var pendingDelete: Product?
    @State private var search = ""

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

                if filteredProducts.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            search.trimmed.isEmpty ? "还没有商品" : "没有找到商品",
                            systemImage: "shippingbox",
                            description: Text(search.trimmed.isEmpty ? "添加商品图片和名称即可保存。" : "试试其他商品名称或 SKU。")
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
        .confirmationDialog("删除商品？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除商品", role: .destructive) {
                guard let product = pendingDelete else { return }
                pendingDelete = nil
                Task { await app.delete(product: product) }
            }
        } message: {
            Text("此商品及其关联的本地图片和记录将被删除。")
        }
    }

    private var filteredProducts: [Product] {
        app.snapshot.products.filter { product in
            search.trimmed.isEmpty || product.name.localizedCaseInsensitiveContains(search.trimmed) || (product.sku?.localizedCaseInsensitiveContains(search.trimmed) == true)
        }.sorted { $0.createdAt > $1.createdAt }
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
                    Text(product.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(MusesTheme.secondaryInk)
                }
                Spacer(minLength: 6)
                VStack(spacing: 8) {
                    Menu {
                        Button("删除商品", role: .destructive, action: deleteAction)
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
}

#if DEBUG
#Preview("History") {
    MusesPreview.environment(.history) { HistoryView() }
}
#endif
