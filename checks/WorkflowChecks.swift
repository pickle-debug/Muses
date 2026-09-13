import SwiftUI
import UIKit

// Run only in an isolated Xcode validation app; writes local SKU data.
@main
struct WorkflowCheckApp: App {
    var body: some Scene {
        WindowGroup { Text("Workflow checks").task { await runChecks() } }
    }

    @MainActor
    private func runChecks() async {
        let app = AppModel()
        while app.isLoadingLocalState { try? await Task.sleep(for: .milliseconds(20)) }
        assert(app.screen == .history && app.selectedTab == .products)
        app.selectTab(.settings)
        app.selectTab(.publish)
        assert(app.isQuickPublishPresented && app.screen == .setup)
        app.dismissQuickPublish()
        assert(!app.isQuickPublishPresented && app.selectedTab == .settings)
        app.selectTab(.products)
        app.startNewProduct()
        assert(app.screen == .sku)
        app.productName = "   "
        let emptyNameSaved = await app.saveProductDraft()
        assert(!emptyNameSaved && app.snapshot.products.isEmpty && app.sku.isEmpty)
        app.alert = nil
        app.productName = "测试玻璃杯"
        let saved = await app.saveProductDraft()
        assert(saved && app.snapshot.products.count == 1)
        let product = app.snapshot.products[0]
        assert(product.sku == "SKU-\(product.id.uuidString)")
        assert(app.screen == .skuDetail(product.id))
        await app.resume(product: product)
        assert(app.screen == .sku && app.productName == product.name)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160))
        for index in 0..<AppModel.maximumSourcePhotoCount {
            let photo = renderer.pngData { context in
                UIColor(hue: CGFloat(index) / 10, saturation: 1, brightness: 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
            }
            await app.addPhoto(data: photo, suggestedExtension: "png")
        }
        assert(app.sourceAssets.count == 9)
        let overflowPhoto = renderer.pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        await app.addPhoto(data: overflowPhoto, suggestedExtension: "png")
        assert(app.sourceAssets.count == 9)
        app.removeSource(app.sourceAssets.last!)
        await app.addPhoto(data: overflowPhoto, suggestedExtension: "png")
        assert(app.sourceAssets.count == 9)
        app.moveSource(app.sourceAssets.last!, by: -1)
        let photoIDs = app.sourceAssets.map(\.id)
        await app.addPhotos(from: [])
        await app.addPhotoFiles([])
        await app.startNewProduct(from: [])
        assert(app.sourceAssets.map(\.id) == photoIDs)
        let savedAgain = await app.saveProductDraft()
        assert(savedAgain && app.snapshot.products.count == 1 && app.sku == product.sku)
        assert(app.snapshot.creations.isEmpty && app.snapshot.jobs.isEmpty)
        let reloaded = AppModel()
        while reloaded.isLoadingLocalState { try? await Task.sleep(for: .milliseconds(20)) }
        let storedProduct = reloaded.snapshot.products.first { $0.id == product.id }!
        await reloaded.resume(product: storedProduct)
        assert(reloaded.screen == .sku && reloaded.operation == .idle)
        assert(reloaded.sourceAssets.map(\.id) == photoIDs && reloaded.sku == product.sku)
        await reloaded.delete(product: storedProduct)
        assert(reloaded.snapshot.products.isEmpty && reloaded.snapshot.productSnapshots.isEmpty)
        print("WORKFLOW CHECKS PASSED: SKU create, nine photos, edit, JSON reload and delete")
        exit(0)
    }
}
