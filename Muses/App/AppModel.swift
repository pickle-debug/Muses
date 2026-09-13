import Foundation
import PhotosUI
import SwiftUI
import UIKit

enum AppScreen: Hashable {
    case setup
    case history
    case skuDetail(MusesID)
    case sku
}

enum ConnectionState: Equatable {
    case idle, testing, connected, preview, failed(String)
}

enum WorkflowOperation: Equatable {
    case idle, working(String), failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    static let maximumSourcePhotoCount = 9

    @Published var screen: AppScreen = .history
    @Published var selectedTab: MTab = .products
    @Published var isQuickPublishPresented = false
    @Published var sku = ""
    @Published var isLoadingLocalState = true
    @Published var snapshot = AppSnapshot()
    @Published var connectionState: ConnectionState = .idle
    @Published var operation: WorkflowOperation = .idle
    @Published var alert: AppAlert?

    @Published var apiKey = ""
    @Published var productName = ""
    @Published var sourceAssets: [LocalAsset] = []

    private(set) var configuration: ProviderConfiguration?
    private let credentialStore: UserDefaultsCredentialStore
    private var snapshotStore: SnapshotStore?
    private var assetStore: AssetStore?
    private var provider: OpenAIStyleProviderClient?
    private var currentProductID: MusesID?
    private var currentSnapshotID: MusesID?

    var isPlaceholderConfiguration: Bool {
        guard let configuration else { return true }
        return configuration.provider.baseUrl.host?.hasSuffix(".invalid") == true
            || configuration.models.text.uppercased().contains("REPLACE_ME")
            || configuration.models.video.uppercased().contains("REPLACE_ME")
    }

    var endpointDisplay: String {
        configuration?.provider.baseUrl.absoluteString ?? "配置不可用"
    }

    var hasStoredCredential: Bool { credentialStore.apiKey() != nil }

    init() {
        credentialStore = UserDefaultsCredentialStore()
        do {
            let snapshots = try SnapshotStore()
            let assets = try AssetStore()
            snapshotStore = snapshots
            assetStore = assets
            Task { await loadLocalState() }
            let config = try ProviderConfigurationLoader.load(allowPlaceholders: true)
            configuration = config
            let containsPlaceholder = config.provider.baseUrl.host?.hasSuffix(".invalid") == true
                || config.models.text.uppercased().contains("REPLACE_ME")
                || config.models.video.uppercased().contains("REPLACE_ME")
            if !containsPlaceholder {
                provider = try OpenAIStyleProviderClient(configuration: config, credentialStore: credentialStore)
            }
        } catch {
            if snapshotStore == nil {
                isLoadingLocalState = false
                alert = AppAlert.from(error)
            } else {
                connectionState = .failed(AppAlert.from(error).message)
            }
        }
    }

    #if DEBUG
    init(previewing: Bool) {
        precondition(previewing)
        isLoadingLocalState = false
        let defaults = UserDefaults(suiteName: "Muses.XcodePreview")!
        credentialStore = UserDefaultsCredentialStore(defaults: defaults)
        configuration = try? ProviderConfigurationLoader.load(allowPlaceholders: true)
    }
    #endif

    func loadLocalState() async {
        defer { isLoadingLocalState = false }
        guard let snapshotStore else { return }
        do {
            snapshot = try await snapshotStore.load()
        } catch {
            alert = AppAlert.from(error)
        }
    }

    func testConnection() async {
        let candidate = apiKey.trimmed
        guard !candidate.isEmpty || credentialStore.apiKey() != nil else {
            connectionState = .failed("请输入临时 Key")
            return
        }
        if isPlaceholderConfiguration {
            connectionState = .failed("开发配置仍是占位地址，无法测试真实连接")
            return
        }
        let previousKey = credentialStore.apiKey()
        if !candidate.isEmpty { credentialStore.setApiKey(candidate) }
        connectionState = .testing
        do {
            _ = try await provider?.testConnection()
            if provider == nil {
                connectionState = .failed("当前 Provider 尚未初始化")
            } else {
                connectionState = .connected
                apiKey = ""
            }
        } catch {
            if !candidate.isEmpty {
                if let previousKey { credentialStore.setApiKey(previousKey) }
                else { credentialStore.deleteApiKey() }
            }
            connectionState = .failed(AppAlert.from(error).message)
        }
    }

    func deleteCredential() {
        credentialStore.deleteApiKey()
        apiKey = ""
        connectionState = .idle
    }

    func startNewProduct() {
        guard !isWorking else { return }
        sku = ""
        currentProductID = UUID()
        currentSnapshotID = nil
        productName = ""
        sourceAssets = []
        operation = .idle
        screen = .sku
    }

    func startNewProduct(from items: [PhotosPickerItem]) async {
        guard !isWorking, !items.isEmpty else { return }
        guard let assetStore else {
            alert = AppAlert(title: "无法导入图片", message: "本地素材存储不可用，请重试。")
            return
        }
        operation = .working("正在读取商品图片")
        defer { operation = .idle }
        let productID = UUID()
        var assets: [LocalAsset] = []
        var failedCount = 0
        for item in items.prefix(Self.maximumSourcePhotoCount) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failedCount += 1
                    continue
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let temporary = FileManager.default.temporaryDirectory.appending(path: "muses-picker-\(UUID().uuidString).\(ext)")
                try data.write(to: temporary, options: .atomic)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let asset = try await assetStore.importSource(from: temporary, productID: productID)
                if !assets.contains(where: { $0.sha256 == asset.sha256 }) { assets.append(asset) }
            } catch {
                failedCount += 1
            }
        }
        guard !assets.isEmpty else {
            try? await assetStore.deleteProject(productID: productID, creationIDs: [])
            alert = AppAlert(title: "无法读取所选图片", message: "请确认图片已从 iCloud 下载、格式有效且每张不超过 30 MB，然后重新选择。")
            return
        }
        // Keep the current draft intact until at least one selected photo is imported.
        operation = .idle
        startNewProduct()
        currentProductID = productID
        sourceAssets = assets
        selectedTab = .products
        isQuickPublishPresented = false
        if failedCount > 0 {
            alert = AppAlert(title: "部分图片未导入", message: "已导入 \(assets.count) 张，另有 \(failedCount) 张无法读取。可以在编辑页重新添加，单张图片不能超过 30 MB。")
        }
    }

    func addPhoto(data: Data, suggestedExtension: String = "jpg") async {
        guard !isWorking, sourceAssets.count < Self.maximumSourcePhotoCount, let productID = currentProductID, let assetStore else { return }
        let temporary = FileManager.default.temporaryDirectory.appending(path: "muses-picker-\(UUID().uuidString).\(suggestedExtension)")
        do {
            try data.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let asset = try await assetStore.importSource(from: temporary, productID: productID)
            guard currentProductID == productID, sourceAssets.count < Self.maximumSourcePhotoCount else { return }
            guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { return }
            sourceAssets.append(asset)
        } catch {
            alert = AppAlert.from(error)
        }
    }

    func addPhotoFile(_ url: URL) async throws {
        guard !isWorking, sourceAssets.count < Self.maximumSourcePhotoCount, let productID = currentProductID, let assetStore else { return }
        let asset = try await assetStore.importSource(from: url, productID: productID)
        guard currentProductID == productID, sourceAssets.count < Self.maximumSourcePhotoCount else { return }
        guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { return }
        sourceAssets.append(asset)
    }

    /// Imports a picker selection as one operation for the currently edited product.
    /// The active product and nine-photo limit are captured before any await.
    func addPhotos(from items: [PhotosPickerItem]) async {
        guard !isWorking, !items.isEmpty, let productID = currentProductID, let assetStore else { return }
        let capacity = max(0, Self.maximumSourcePhotoCount - sourceAssets.count)
        guard capacity > 0 else { alert = AppAlert(title: "图片已达上限", message: "每个商品最多添加 9 张图片。"); return }
        operation = .working("正在读取商品图片")
        defer { operation = .idle }
        var imported = 0, failed = 0, skipped = 0
        for item in items {
            guard !Task.isCancelled, currentProductID == productID else { return }
            guard sourceAssets.count < Self.maximumSourcePhotoCount else { skipped += 1; continue }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { failed += 1; continue }
                guard !Task.isCancelled, currentProductID == productID else { return }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let temporary = FileManager.default.temporaryDirectory.appending(path: "muses-picker-\(UUID().uuidString).\(ext)")
                try data.write(to: temporary, options: .atomic)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let asset = try await assetStore.importSource(from: temporary, productID: productID)
                guard !Task.isCancelled, currentProductID == productID else { return }
                guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { skipped += 1; continue }
                guard sourceAssets.count < Self.maximumSourcePhotoCount else { break }
                sourceAssets.append(asset); imported += 1
            } catch { failed += 1 }
        }
        if failed > 0 || skipped > 0 {
            alert = AppAlert(title: imported > 0 ? "部分图片未导入" : "图片未导入", message: "已添加 \(imported) 张" + (failed > 0 ? "，\(failed) 张读取失败" : "") + (skipped > 0 ? "，\(skipped) 张重复或超出 9 张上限" : "") + "。")
        }
    }

    /// Imports file URLs as one operation for the currently edited product.
    func addPhotoFiles(_ urls: [URL]) async {
        guard !isWorking, !urls.isEmpty, let productID = currentProductID, let assetStore else { return }
        let capacity = max(0, Self.maximumSourcePhotoCount - sourceAssets.count)
        guard capacity > 0 else { alert = AppAlert(title: "图片已达上限", message: "每个商品最多添加 9 张图片。"); return }
        operation = .working("正在导入商品图片")
        defer { operation = .idle }
        var imported = 0, failed = 0, skipped = 0
        for url in urls {
            guard !Task.isCancelled, currentProductID == productID else { return }
            guard sourceAssets.count < Self.maximumSourcePhotoCount else { skipped += 1; continue }
            let accessible = url.startAccessingSecurityScopedResource()
            defer { if accessible { url.stopAccessingSecurityScopedResource() } }
            do {
                let asset = try await assetStore.importSource(from: url, productID: productID)
                guard !Task.isCancelled, currentProductID == productID else { return }
                guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { skipped += 1; continue }
                guard sourceAssets.count < Self.maximumSourcePhotoCount else { break }
                sourceAssets.append(asset); imported += 1
            } catch { failed += 1 }
        }
        if failed > 0 || skipped > 0 {
            alert = AppAlert(title: imported > 0 ? "部分图片未导入" : "图片未导入", message: "已添加 \(imported) 张" + (failed > 0 ? "，\(failed) 张读取失败" : "") + (skipped > 0 ? "，\(skipped) 张重复或超出 9 张上限" : "") + "。")
        }
    }

    func removeSource(_ asset: LocalAsset) {
        sourceAssets.removeAll { $0.id == asset.id }
    }

    func moveSource(from offsets: IndexSet, to destination: Int) {
        sourceAssets.move(fromOffsets: offsets, toOffset: destination)
    }

    func moveSource(_ asset: LocalAsset, by offset: Int) {
        guard let index = sourceAssets.firstIndex(where: { $0.id == asset.id }) else { return }
        let destination = min(max(index + offset, 0), sourceAssets.count - 1)
        guard destination != index else { return }
        sourceAssets.swapAt(index, destination)
    }

    func url(for asset: LocalAsset?) async -> URL? {
        guard let asset, let assetStore else { return nil }
        return try? await assetStore.url(for: asset)
    }

    func resume(product: Product) async {
        guard !isWorking else { return }
        startNewProduct()
        currentProductID = product.id
        currentSnapshotID = product.currentSnapshotID
        productName = product.name
        sku = product.sku ?? ""
        guard let facts = snapshot.productSnapshots.first(where: { $0.id == product.currentSnapshotID }) else { return }
        sourceAssets = facts.sourceAssetIDs.compactMap { id in snapshot.assets.first(where: { $0.id == id }) }
    }

    func delete(product: Product) async {
        guard !isWorking else { return }
        let snapshotIDs = Set(snapshot.productSnapshots.filter { $0.productID == product.id }.map(\.id))
        let creationIDs = snapshot.creations.filter { snapshotIDs.contains($0.productSnapshotID) }.map(\.id)
        do {
            try await commit { state in
                let promptVersionIDs = Set(state.promptVersions.filter { snapshotIDs.contains($0.productSnapshotID) }.map(\.id))
                let currentJobIDs = state.creations.filter { creationIDs.contains($0.id) }.flatMap { [$0.imageJobID, $0.videoJobID, $0.copyJobID].compactMap { $0 } }
                let jobIDs = Set(currentJobIDs + state.jobs.filter { job in
                    job.creationID.map(creationIDs.contains) == true
                        || job.promptVersionID.map(promptVersionIDs.contains) == true
                }.map(\.id))
                let assetIDs = Set(state.productSnapshots.filter { snapshotIDs.contains($0.id) }.flatMap(\.sourceAssetIDs) + state.jobs.filter { jobIDs.contains($0.id) }.flatMap(\.outputAssetIDs))
                state.products.removeAll { $0.id == product.id }
                state.productSnapshots.removeAll { snapshotIDs.contains($0.id) }
                state.creations.removeAll { creationIDs.contains($0.id) }
                state.jobs.removeAll { jobIDs.contains($0.id) }
                state.assets.removeAll { assetIDs.contains($0.id) }
                state.reviews.removeAll { assetIDs.contains($0.assetID) }
                state.promptVersions.removeAll { promptVersionIDs.contains($0.id) }
                state.copyPackages.removeAll { creationIDs.contains($0.creationID) }
                state.exportRecords.removeAll { creationIDs.contains($0.creationID) }
            }
            do {
                try await assetStore?.deleteProject(productID: product.id, creationIDs: creationIDs)
            } catch {
                alert = AppAlert(title: "项目已删除", message: "本地记录已删除，但部分媒体文件未能清理；系统下次维护时可再次清理。")
            }
        } catch { alert = AppAlert.from(error) }
    }

    private func commit(_ mutation: (inout AppSnapshot) throws -> Void) async throws {
        guard let snapshotStore else { throw AppError.safe("PERSISTENCE_UNAVAILABLE", "本地存储不可用") }
        var updated = snapshot
        try mutation(&updated)
        updated.updatedAt = .now
        try await snapshotStore.save(updated)
        snapshot = updated
    }

    private func makeProductSnapshot(id: MusesID, productID: MusesID) -> ProductSnapshot {
        let previous = snapshot.productSnapshots.first { $0.id == currentSnapshotID }
        return ProductSnapshot(
            id: id, productID: productID, sourceAssetIDs: sourceAssets.map(\.id),
            category: previous?.category, material: previous?.material, specification: previous?.specification,
            colors: previous?.colors ?? [], visiblePatterns: previous?.visiblePatterns ?? [],
            visibleText: previous?.visibleText ?? [], audience: previous?.audience,
            verifiedSellingPoints: previous?.verifiedSellingPoints ?? [], lockedFeatures: previous?.lockedFeatures ?? [],
            uncertainFields: previous?.uncertainFields ?? [], rightsConfirmed: previous?.rightsConfirmed ?? false,
            confirmedAt: previous?.confirmedAt, fieldConfirmations: previous?.fieldConfirmations
        )
    }
}

extension AppModel {
    var isWorking: Bool {
        if case .working = operation { return true }
        return false
    }

    var activeProduct: Product? { snapshot.products.first { $0.id == currentProductID } }

    func selectTab(_ tab: MTab) {
        guard !isWorking else { return }
        if tab == .publish {
            isQuickPublishPresented = true
        } else {
            selectedTab = tab
            screen = tab == .settings ? .setup : .history
            isQuickPublishPresented = false
        }
    }

    func dismissQuickPublish() {
        guard !isWorking else { return }
        isQuickPublishPresented = false
    }

    func showProduct(_ product: Product) {
        guard !isWorking else { return }
        screen = .skuDetail(product.id)
    }

    func creations(for productID: MusesID) -> [Creation] {
        let ids = Set(snapshot.productSnapshots.filter { $0.productID == productID }.map(\.id))
        return snapshot.creations.filter { ids.contains($0.productSnapshotID) }.sorted { $0.createdAt < $1.createdAt }
    }

    func versionLabel(_ creation: Creation) -> String {
        let productID = snapshot.productSnapshots.first { $0.id == creation.productSnapshotID }?.productID
        let versions = productID.map { creations(for: $0) } ?? []
        return "V\(creation.versionNumber ?? ((versions.firstIndex { $0.id == creation.id } ?? 0) + 1))"
    }

    @discardableResult
    func saveProductDraft(navigate: Bool = true) async -> Bool {
        guard !isWorking, let productID = currentProductID else { return false }
        guard !productName.trimmed.isEmpty else {
            alert = AppAlert(title: "补全商品资料", message: "请填写商品名称，图片可稍后补充。")
            return false
        }
        let generatedSKU = sku.trimmed.isEmpty ? "SKU-\(productID.uuidString)" : sku.trimmed
        guard !snapshot.products.contains(where: { $0.id != productID && $0.sku?.lowercased() == generatedSKU.lowercased() }) else {
            alert = AppAlert(title: "SKU 已存在", message: "请打开已有商品，或使用不同的 SKU 编号。")
            return false
        }
        operation = .working("正在保存商品")
        defer { operation = .idle }
        let snapshotID = UUID()
        let facts = makeProductSnapshot(id: snapshotID, productID: productID)
        let product = Product(id: productID, name: productName.trimmed, createdAt: activeProduct?.createdAt ?? .now, currentSnapshotID: snapshotID, status: activeProduct?.status ?? .draft, sku: generatedSKU)
        do {
            try await commit { state in
                state.products.removeAll { $0.id == productID }
                state.products.append(product)
                state.productSnapshots.append(facts)
                state.assets.append(contentsOf: sourceAssets.filter { asset in !state.assets.contains { $0.id == asset.id } })
            }
            sku = generatedSKU
            currentSnapshotID = snapshotID
            if navigate { screen = .skuDetail(productID) }
            return true
        } catch { alert = AppAlert.from(error); return false }
    }

    func importSKUFile(_ url: URL) async {
        guard !isWorking else { return }
        operation = .working("正在导入 SKU")
        defer { operation = .idle }
        let accessible = url.startAccessingSecurityScopedResource()
        defer { if accessible { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_097_152 else { throw AppError.safe("IMPORT_TOO_LARGE", "文件不能超过 2 MB。") }
            let rows = try SKUImport.parse(Data(contentsOf: url), fileExtension: url.pathExtension)
            let existing = Set(snapshot.products.compactMap { $0.sku?.lowercased() })
            guard let duplicate = rows.first(where: { existing.contains($0.sku.lowercased()) }) else {
                try await commit { state in
                    for row in rows {
                        let productID = UUID(), snapshotID = UUID()
                        state.products.append(Product(id: productID, name: row.name, createdAt: .now, currentSnapshotID: snapshotID, status: .draft, sku: row.sku))
                        state.productSnapshots.append(ProductSnapshot(id: snapshotID, productID: productID, sourceAssetIDs: [], colors: [], visiblePatterns: [], visibleText: [], verifiedSellingPoints: [row.sellingPoint], lockedFeatures: [], uncertainFields: [], rightsConfirmed: false))
                    }
                }
                alert = AppAlert(title: "已导入 \(rows.count) 个 SKU", message: "可在商品库查看并编辑已导入的商品。")
                return
            }
            throw AppError.safe("SKU_DUPLICATE", "SKU「\(duplicate.sku)」已存在。本次未导入，请修改文件后重试。")
        } catch { alert = AppAlert.from(error) }
    }

    func saveTracking(creationID: MusesID, postURL: String, publishedAt: Date, metrics: PostMetrics) async throws {
        guard !isWorking else { throw AppError.safe("BUSY", "请等待当前操作完成。") }
        try metrics.validate()
        guard let url = URL(string: postURL.trimmed), let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") || host == "xhslink.com" || host.hasSuffix(".xhslink.com"),
              publishedAt <= .now else {
            throw AppError.safe("POST_INVALID", "请填写有效的小红书帖子链接，发布时间不能在未来。")
        }
        guard let creation = snapshot.creations.first(where: { $0.id == creationID }), [.ready, .saved].contains(creation.status), creation.isPreview != true else {
            throw AppError.safe("VERSION_NOT_READY", "真实图文版本完成后，才可登记发布数据。")
        }
        operation = .working("正在保存跟进数据")
        defer { operation = .idle }
        try await commit { state in
            guard let index = state.creations.firstIndex(where: { $0.id == creationID }) else { return }
            var tracking = state.creations[index].tracking ?? PostTracking(postURL: postURL.trimmed, publishedAt: publishedAt, samples: [])
            tracking.postURL = postURL.trimmed
            tracking.publishedAt = publishedAt
            tracking.samples.append(metrics)
            state.creations[index].tracking = tracking
        }
    }
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func from(_ error: Error) -> AppAlert {
        if let error = error as? AppError { return AppAlert(title: "暂时无法完成", message: error.userMessage) }
        return AppAlert(title: "暂时无法完成", message: "发生未知错误，请稍后重试。")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
    var componentsList: [String] {
        components(separatedBy: CharacterSet(charactersIn: "、,，\n"))
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }
}
