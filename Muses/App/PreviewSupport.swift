import SwiftUI

#if DEBUG
/// Stable, non-persistent state shared by all Xcode Canvas previews.
@MainActor
enum MusesPreview {
    private static let productID = UUID(uuidString: "4CFE7F1C-6A3C-4D48-AB0C-0A2E41B77E10")!
    private static let snapshotID = UUID(uuidString: "E8796E0E-2BB4-4495-AC5D-CCACBFA4B37E")!

    static func model(for screen: AppScreen) -> AppModel {
        let app = AppModel(previewing: true)
        app.screen = screen
        app.connectionState = .preview
        app.productName = "透明波点玻璃杯"
        app.sku = "SKU-\(productID.uuidString)"
        let product = Product(id: productID, name: app.productName, createdAt: .now, currentSnapshotID: snapshotID, status: .draft, sku: app.sku)
        let facts = ProductSnapshot(id: snapshotID, productID: productID, sourceAssetIDs: [], colors: [], visiblePatterns: [], visibleText: [], verifiedSellingPoints: [], lockedFeatures: [], uncertainFields: [], rightsConfirmed: false)
        app.snapshot = AppSnapshot(products: [product], productSnapshots: [facts])
        return app
    }

    @ViewBuilder
    static func environment<Content: View>(_ screen: AppScreen, @ViewBuilder content: () -> Content) -> some View {
        content().environmentObject(model(for: screen))
    }
}
#endif
