import SwiftUI

struct SKUDetailView: View {
    @EnvironmentObject private var app: AppModel
    let productID: MusesID

    private var product: Product? { app.snapshot.products.first { $0.id == productID } }
    private var photos: [LocalAsset] {
        guard let product,
              let saved = app.snapshot.productSnapshots.first(where: { $0.id == product.currentSnapshotID }) else { return [] }
        return saved.sourceAssetIDs.compactMap { id in app.snapshot.assets.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let product {
                if photos.isEmpty {
                    ContentUnavailableView("暂无商品图片", systemImage: "photo")
                        .frame(height: 280)
                } else {
                    TabView {
                        ForEach(photos) { asset in
                            AssetImage(asset: asset, contentMode: .fit)
                                .padding(.bottom, 28)
                        }
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 280)
                    .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("sku.detail.photos")
                }
                Text(product.name)
                    .font(.title2.bold())
                    .accessibilityIdentifier("sku.detail.name")
            } else {
                ContentUnavailableView("商品不存在", systemImage: "shippingbox")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { app.screen = .history } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("返回商品列表")
                .accessibilityIdentifier("sku.detail.back")
                Text("商品详情").font(.headline)
                Spacer()
                if let product {
                    Button("编辑") { Task { await app.resume(product: product) } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sku.detail.edit")
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 20)
        }
        .musesPage()
        .buttonStyle(.plain)
        .disabled(app.isWorking)
    }
}
