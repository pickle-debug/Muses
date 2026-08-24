import SwiftUI

#if DEBUG
/// Stable, non-persistent state shared by all Xcode Canvas previews.
@MainActor
enum MusesPreview {
    private static let productID = UUID(uuidString: "4CFE7F1C-6A3C-4D48-AB0C-0A2E41B77E10")!
    private static let snapshotID = UUID(uuidString: "E8796E0E-2BB4-4495-AC5D-CCACBFA4B37E")!
    private static let creationID = UUID(uuidString: "5F6E09C4-EF64-4EF8-9B6D-2BB36D1D80C8")!
    private static let imageJobID = UUID(uuidString: "2EAB3DC8-5AF9-49D2-AFC6-510F4C835B34")!
    private static let videoJobID = UUID(uuidString: "C1EEFE82-3B4E-49C4-9E2D-AD7F9B57F714")!

    private static let sourceAssets = [
        asset(id: "F1B9E912-314C-4BB1-A2B8-1B053F4ED7C0", kind: .sourceImage, path: "preview/source-1.jpg"),
        asset(id: "8BD18E86-0A25-4F4C-8B71-BD7DFB7CBF62", kind: .sourceImage, path: "preview/source-2.jpg"),
        asset(id: "E3B6ECF5-2B51-4E6D-98C7-7B7A3DD04845", kind: .sourceImage, path: "preview/source-3.jpg")
    ]

    private static let generatedImage = asset(id: "1BB6688A-D0A4-40D5-BE99-2C3B0B227D2C", kind: .generatedImage, path: "preview/generated.jpg")
    private static let generatedVideo = asset(id: "B4ED0B31-EA66-484E-8EC8-1C836D6D98C6", kind: .generatedVideo, path: "preview/generated.mp4", mimeType: "video/mp4")

    static func model(for screen: AppScreen) -> AppModel {
        let app = AppModel(previewing: true)
        app.screen = screen
        app.connectionState = .demo
        app.productName = "透明波点玻璃杯"
        app.sellingPoint = "高透玻璃，适合日常饮水与冷饮"
        app.category = "家居用品"
        app.material = "玻璃"
        app.specification = "约 350 ml"
        app.colorsText = "透明"
        app.patternsText = "白色波点"
        app.visibleText = ""
        app.audience = "喜欢清爽家居风格的人群"
        app.lockedFeaturesText = "外形比例、透明材质、白色波点"
        app.uncertainFields = []
        app.rightsConfirmed = true
        app.factConfirmationStates = Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0, .confirmed) })
        app.sourceAssets = sourceAssets
        app.generatedImageAsset = generatedImage
        app.generatedVideoAsset = generatedVideo
        app.selectedImageChecks = []
        app.selectedVideoChecks = []
        app.copyTitles = ["透明波点玻璃杯，把清爽感带进每一天", "一只好看的玻璃杯，日常喝水也有仪式感", "白色波点与高透玻璃的轻盈组合"]
        app.selectedTitleIndex = 0
        app.copyBody = "高透玻璃搭配白色波点，轻盈清爽，适合日常饮水和冷饮。以实物为准，不夸大材质与使用效果。"
        app.copyTopics = ["玻璃杯", "家居好物", "日常饮水"]
        app.exportRecord = ExportRecord(
            id: UUID(), creationID: creationID,
            livePhotoStatus: .saved, imageStatus: .saved, videoStatus: .saved, copyStatus: .saved,
            createdAt: .now, updatedAt: .now
        )

        let product = Product(id: productID, name: app.productName, createdAt: .now, currentSnapshotID: snapshotID, status: .completed)
        let facts = ProductSnapshot(
            id: snapshotID, productID: productID, sourceAssetIDs: sourceAssets.map(\.id),
            category: app.category, material: app.material, specification: app.specification,
            colors: app.colorsText.componentsList, visiblePatterns: app.patternsText.componentsList,
            visibleText: [], audience: app.audience, verifiedSellingPoints: [app.sellingPoint],
            lockedFeatures: app.lockedFeaturesText.componentsList, uncertainFields: [], rightsConfirmed: true,
            confirmedAt: .now,
            fieldConfirmations: Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0.rawValue, .confirmed) })
        )
        let creation = Creation(
            id: creationID, productSnapshotID: snapshotID, platform: .xiaohongshu,
            template: .handheldLifestyleV1, imageJobID: imageJobID, videoJobID: videoJobID,
            copyJobID: nil, status: .saved, createdAt: .now, updatedAt: .now
        )
        let imageJob = GenerationJob(
            id: imageJobID, kind: .image, creationID: creationID, idempotencyKey: UUID(),
            model: "preview-image-model", promptVersionID: nil, status: .succeeded,
            outputAssetIDs: [generatedImage.id]
        )
        let videoJob = GenerationJob(
            id: videoJobID, kind: .video, creationID: creationID, providerTaskID: "preview-video-task",
            idempotencyKey: UUID(), model: "preview-video-model", promptVersionID: nil,
            status: .succeeded, outputAssetIDs: [generatedVideo.id]
        )
        app.snapshot = AppSnapshot(
            products: [product], productSnapshots: [facts], creations: [creation],
            jobs: [imageJob, videoJob], assets: sourceAssets + [generatedImage, generatedVideo],
            copyPackages: [StoredCopyPackage(id: UUID(), creationID: creationID, titles: app.copyTitles, selectedTitleIndex: 0, body: app.copyBody, topics: app.copyTopics, createdAt: .now, updatedAt: .now)],
            exportRecords: [app.exportRecord!]
        )

        switch screen {
        case .factConfirmation:
            app.factConfirmationStates = Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0, .pending) })
            app.factConfirmationStates[.sellingPoint] = .confirmed
            app.rightsConfirmed = false
        case .imageGeneration:
            app.operation = .working("AI 正在生成商品事实已确认的图片")
        case .videoGeneration:
            app.operation = .working("正在查询供应商动态任务")
        default:
            break
        }
        return app
    }

    @ViewBuilder
    static func environment<Content: View>(_ screen: AppScreen, @ViewBuilder content: () -> Content) -> some View {
        content().environmentObject(model(for: screen))
    }

    private static func asset(id: String, kind: AssetKind, path: String, mimeType: String = "image/jpeg") -> LocalAsset {
        LocalAsset(
            id: UUID(uuidString: id)!, kind: kind, relativePath: path, mimeType: mimeType,
            byteCount: 1, sha256: "preview-\(id)", createdAt: .now
        )
    }
}
#endif
