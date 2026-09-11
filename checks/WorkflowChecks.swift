import SwiftUI
import UIKit

// Run in an isolated simulator app; never calls a provider or writes to Photos.
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
        for tab in WorkspaceTab.allCases {
            app.selectTab(tab)
            assert((tab == .publish ? app.isQuickPublishPresented : app.selectedTab == tab) && app.screen == (tab == .settings ? .setup : .history))
        }
        app.selectTab(.settings)
        app.selectTab(.publish)
        assert(app.selectedTab == .settings && app.isQuickPublishPresented)
        app.dismissQuickPublish()
        assert(app.selectedTab == .settings && app.screen == .setup && !app.isQuickPublishPresented)
        app.selectTab(.publish)
        app.alert = nil
        app.startNewProduct()
        app.sku = "CHECK-\(UUID().uuidString)"; app.productName = "测试玻璃杯"; app.sellingPoint = "杯身刻度清晰"
        assert(!app.hasStoredCredential)
        let saved = await app.saveProductDraft()
        assert(saved && app.snapshot.products.count == 1)
        let productID = app.snapshot.products[0].id
        app.enterPreviewMode()
        await app.resume(product: app.snapshot.products[0])
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160))
        let image = renderer.pngData { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        await app.addPhoto(data: image, suggestedExtension: "png")
        assert(app.sourceAssets.count == 1 && app.sourceAssets[0].relativePath.hasSuffix(".png"))
        await app.recognizeProduct()
        assert(app.screen == .factConfirmation)
        app.colorsText = "透明"; app.lockedFeaturesText = "杯身轮廓、刻度"
        for field in FactField.allCases {
            app.setFactStatus([.sellingPoint, .lockedFeatures, .colors].contains(field) ? .confirmed : .notApplicable, for: field)
        }
        app.rightsConfirmed = true
        assert(app.canConfirmFacts)
        await app.confirmFactsAndGenerate()
        await app.confirmFactsAndGenerate() // double taps must not create a second version
        while app.isWorking { try? await Task.sleep(for: .milliseconds(30)) }
        assert(app.snapshot.creations.count == 1 && app.screen == .imageReview)
        app.selectedImageChecks = Set(app.imageReviewItems)
        await app.approveImageAndGenerateCopy()
        assert(app.screen == .copyResult && app.snapshot.creations[0].videoJobID == nil)
        app.copyBody = "保留的第一版文案"
        await app.confirmCopy()
        let v1 = app.snapshot.creations[0]
        await app.prepareNextVersion(for: app.snapshot.products[0])
        assert(app.screen == .factConfirmation)
        app.revisionNote = "突出刻度"
        await app.confirmFactsAndGenerate()
        while app.isWorking { try? await Task.sleep(for: .milliseconds(30)) }
        assert(app.snapshot.creations.count == 2)
        let v2 = app.snapshot.creations[1]
        assert(v1.productSnapshotID != v2.productSnapshotID && v2.versionNumber == 2)
        assert(app.snapshot.productSnapshots.contains { $0.id == v1.productSnapshotID })
        assert(app.snapshot.copyPackages.first { $0.creationID == v1.id }?.body == "保留的第一版文案")
        app.selectedImageChecks = Set(app.imageReviewItems)
        await app.approveImageAndGenerateCopy()
        await app.resume(product: app.snapshot.products[0], creation: v1)
        assert(app.copyBody == "保留的第一版文案" && app.activeCreation?.id == v1.id)
        assert(app.isCurrentVersionReadOnly)
        app.copyBody = "不得覆盖旧版"
        await app.confirmCopy()
        assert(app.snapshot.copyPackages.first { $0.creationID == v1.id }?.body == "保留的第一版文案")
        // Simulate a completed real version for local metrics validation (no generated output claim).
        app.snapshot.creations[0].isPreview = false
        let metrics = PostMetrics(views: 1000, likes: 20, saves: 5, comments: 2, inquiries: 10, orders: 3, revenue: 99.9, note: "人工确认订单")
        do {
            try await app.saveTracking(creationID: v1.id, postURL: "https://www.xiaohongshu.com/explore/check", publishedAt: .now, metrics: metrics)
            try await app.saveTracking(creationID: v1.id, postURL: "https://www.xiaohongshu.com/explore/check", publishedAt: .now, metrics: metrics)
            assert(app.snapshot.creations[0].tracking?.samples.count == 2)
            assert(app.snapshot.creations[1].tracking == nil)
            let reloaded = AppModel()
            while reloaded.isLoadingLocalState { try? await Task.sleep(for: .milliseconds(20)) }
            assert(reloaded.snapshot.creations.count == 2 && reloaded.snapshot.creations[0].tracking?.samples.count == 2)
            assert(reloaded.creations(for: productID).count == 2)
            let file = FileManager.default.temporaryDirectory.appending(path: "sku-check.csv")
            try Data("SKU,商品名称,卖点\nIMPORT-1,杯子,有刻度\nIMPORT-2,水壶,带提手".utf8).write(to: file)
            await reloaded.importSKUFile(file)
            assert(reloaded.snapshot.products.count == 3)
            await reloaded.importSKUFile(file)
            assert(reloaded.snapshot.products.count == 3) // no partial or duplicate import
            print("WORKFLOW CHECKS PASSED: no-key draft, image import, V1/V2 preservation, direct copy, tracking and reload")
        } catch { assertionFailure(error.localizedDescription) }
        exit(0)
    }
}
