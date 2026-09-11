import Foundation
import SwiftUI
import UIKit

enum AppScreen: Hashable {
    case setup
    case history
    case productDetail(MusesID)
    case product
    case factConfirmation
    case imageGeneration
    case imageReview
    case videoGeneration
    case videoReview
    case copyResult
    case saveResult
}

enum ConnectionState: Equatable {
    case idle, testing, connected, preview, failed(String)
}

enum WorkflowOperation: Equatable {
    case idle, working(String), failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: AppScreen = .history
    @Published var selectedTab: MTab = .products
    @Published var isQuickPublishPresented = false
    @Published var sku = ""
    @Published var revisionNote = ""
    @Published var isLoadingLocalState = true
    @Published var snapshot = AppSnapshot()
    @Published var connectionState: ConnectionState = .idle
    @Published var operation: WorkflowOperation = .idle
    @Published var alert: AppAlert?

    @Published var apiKey = ""
    @Published var productName = ""
    @Published var sellingPoint = ""
    @Published var sourceAssets: [LocalAsset] = []
    @Published var category = ""
    @Published var material = ""
    @Published var specification = ""
    @Published var colorsText = ""
    @Published var patternsText = ""
    @Published var visibleText = ""
    @Published var audience = ""
    @Published var lockedFeaturesText = ""
    @Published var uncertainFields: [String] = []
    @Published var factConfirmationStates: [FactField: FactConfirmationStatus] = [:]
    @Published var rightsConfirmed = false

    @Published var generatedImageAsset: LocalAsset?
    @Published var generatedVideoAsset: LocalAsset?
    @Published var selectedImageChecks: Set<String> = []
    @Published var selectedVideoChecks: Set<String> = []
    @Published var copyTitles: [String] = []
    @Published var selectedTitleIndex = 0
    @Published var copyBody = ""
    @Published var copyTopics: [String] = []
    @Published var exportRecord: ExportRecord?
    @Published var isImageSubmissionUnknown = false
    @Published var isVideoSubmissionUnknown = false

    private(set) var configuration: ProviderConfiguration?
    private let credentialStore: UserDefaultsCredentialStore
    private var snapshotStore: SnapshotStore?
    private var assetStore: AssetStore?
    private var provider: OpenAIStyleProviderClient?
    private let photoLibrary = PhotoLibraryService()
    private var livePhotoService: (any LivePhotoServing)?
    private var pollingTask: Task<Void, Never>?

    private var currentProductID: MusesID?
    private var currentSnapshotID: MusesID?
    private var currentCreationID: MusesID?
    private var imageJobID: MusesID?
    private var videoJobID: MusesID?
    private var imageGenerationTask: Task<Void, Never>?
    private var videoGenerationTask: Task<Void, Never>?
    private var imageSubmissionAccepted = false

    let imageReviewItems = ["外形与轮廓", "颜色与透明度", "图案与纹理", "商品文字", "材质质感", "规格关系", "未增加部件或赠品"]
    let videoReviewItems = ["商品未变形或闪烁", "手部接触自然", "背景没有跳变", "外形、颜色与图案保持一致"]

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

    var imageModelName: String { configuration?.models.image ?? "—" }
    var videoSummary: String {
        guard let config = configuration else { return "3–5 秒 · 720p · 静音" }
        return "\(config.video.durationSeconds) 秒 · \(config.video.resolution) · 静音"
    }

    var canConfirmFacts: Bool {
        FactField.allCases.allSatisfy { field in
            switch factStatus(for: field) {
            case .pending:
                return false
            case .confirmed:
                return canConfirmFact(field)
            case .notApplicable:
                return field != .lockedFeatures && field != .sellingPoint
            }
        } && rightsConfirmed
    }

    var imageReviewComplete: Bool { selectedImageChecks.count == imageReviewItems.count }
    var videoReviewComplete: Bool { selectedVideoChecks.count == videoReviewItems.count }
    var hasRealGeneratedMedia: Bool { generatedImageAsset?.kind == .generatedImage && generatedVideoAsset?.kind == .generatedVideo }
    var canRetryImageDownload: Bool {
        guard let job = currentImageJob else { return false }
        return job.providerResultURL != nil && job.status == .downloading
    }
    var canCreateReplacementImageJob: Bool { currentImageJob?.status.canCreateReplacement == true }
    var canResumeVideoJob: Bool { currentVideoJob?.providerTaskID != nil && currentVideoJob?.status.shouldResume == true }
    var canRetryVideoDownload: Bool {
        guard let job = currentVideoJob else { return false }
        return job.providerResultURL != nil && job.status == .downloading
    }
    var canCreateReplacementVideoJob: Bool { currentVideoJob?.status.canCreateReplacement == true }

    init() {
        credentialStore = UserDefaultsCredentialStore()
        do {
            let snapshots = try SnapshotStore()
            let assets = try AssetStore()
            snapshotStore = snapshots
            assetStore = assets
            livePhotoService = LivePhotoService()
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
            snapshot = try await snapshotStore.normalizeInterruptedSubmissions()
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

    func enterPreviewMode() {
        connectionState = .preview
    }

    func saveSetupAndContinue() {
        guard connectionState == .connected || connectionState == .preview else { return }
        selectTab(.publish)
    }

    func deleteCredential() {
        credentialStore.deleteApiKey()
        apiKey = ""
        connectionState = .idle
    }

    func startNewProduct() {
        guard !isWorking else { return }
        sku = ""
        revisionNote = ""
        pollingTask?.cancel()
        imageGenerationTask?.cancel()
        videoGenerationTask?.cancel()
        currentProductID = UUID()
        currentSnapshotID = nil
        currentCreationID = nil
        imageJobID = nil
        videoJobID = nil
        productName = ""
        sellingPoint = ""
        sourceAssets = []
        category = ""
        material = ""
        specification = ""
        colorsText = ""
        patternsText = ""
        visibleText = ""
        audience = ""
        lockedFeaturesText = ""
        uncertainFields = []
        factConfirmationStates = [:]
        rightsConfirmed = false
        generatedImageAsset = nil
        generatedVideoAsset = nil
        selectedImageChecks = []
        selectedVideoChecks = []
        copyTitles = []
        copyBody = ""
        copyTopics = []
        exportRecord = nil
        isImageSubmissionUnknown = false
        isVideoSubmissionUnknown = false
        operation = .idle
        screen = .product
    }

    func addPhoto(data: Data, suggestedExtension: String = "jpg") async {
        guard sourceAssets.count < 6, let productID = currentProductID, let assetStore else { return }
        let temporary = FileManager.default.temporaryDirectory.appending(path: "muses-picker-\(UUID().uuidString).\(suggestedExtension)")
        do {
            try data.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let asset = try await assetStore.importSource(from: temporary, productID: productID)
            guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { return }
            sourceAssets.append(asset)
        } catch {
            alert = AppAlert.from(error)
        }
    }

    func addPhotoFile(_ url: URL) async throws {
        guard !isWorking, sourceAssets.count < 6, let productID = currentProductID, let assetStore else { return }
        let asset = try await assetStore.importSource(from: url, productID: productID)
        guard !sourceAssets.contains(where: { $0.sha256 == asset.sha256 }) else { return }
        sourceAssets.append(asset)
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

    func recognizeProduct() async {
        guard !isWorking, requireAIService() else { return }
        guard let productID = currentProductID, !productName.trimmed.isEmpty, !sellingPoint.trimmed.isEmpty else {
            alert = AppAlert(title: "信息不完整", message: "请填写商品名称和一句话真实卖点。")
            return
        }
        let minimum = connectionState == .preview ? 1 : 3
        guard sourceAssets.count >= minimum else {
            alert = AppAlert(title: "还需要更多角度", message: "真实调用前请至少选择 3 张商品图；预览模式可用 1 张继续。")
            return
        }
        operation = .working("AI 正在识别商品事实")
        do {
            let factDraft: ProductFactDraft
            if connectionState == .preview {
                try await Task.sleep(for: .milliseconds(700))
                factDraft = ProductFactDraft(
                    category: "家居用品", material: "待确认", specification: "待确认",
                    colors: ["以实物图为准"], visiblePatterns: [], visibleText: [],
                    lockedFeatures: ["外形比例", "颜色与材质", "图案及文字"], uncertainFields: ["材质", "规格"]
                )
            } else {
                let urls = await sourceURLs()
                guard let provider else { throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用") }
                factDraft = try await provider.extractProductFacts(.init(productName: productName, sellingPoint: sellingPoint, referenceImageURLs: urls, idempotencyKey: UUID()))
            }
            category = factDraft.category ?? ""
            material = factDraft.material ?? ""
            specification = factDraft.specification ?? ""
            colorsText = factDraft.colors.joined(separator: "、")
            patternsText = factDraft.visiblePatterns.joined(separator: "、")
            visibleText = factDraft.visibleText.joined(separator: "、")
            lockedFeaturesText = factDraft.lockedFeatures.joined(separator: "、")
            uncertainFields = factDraft.uncertainFields
            factConfirmationStates = Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0, .pending) })
            factConfirmationStates[.sellingPoint] = .confirmed

            let snapshotID = UUID()
            currentSnapshotID = snapshotID
            let product = Product(id: productID, name: productName.trimmed, createdAt: snapshot.products.first(where: { $0.id == productID })?.createdAt ?? .now, currentSnapshotID: snapshotID, status: .factsPending, sku: sku.nilIfEmpty)
            let factSnapshot = makeProductSnapshot(id: snapshotID, productID: productID, confirmed: false)
            try await commit { state in
                state.products.removeAll { $0.id == productID }
                state.products.append(product)
                state.productSnapshots.append(factSnapshot)
                state.assets.append(contentsOf: sourceAssets.filter { asset in !state.assets.contains(where: { $0.id == asset.id }) })
            }
            operation = .idle
            isImageSubmissionUnknown = false
            screen = .factConfirmation
        } catch {
            operation = .failed(AppAlert.from(error).message)
        }
    }

    func confirmFactsAndGenerate() async {
        guard !isWorking, requireAIService(), canConfirmFacts, let productID = currentProductID, let oldSnapshotID = currentSnapshotID else { return }
        guard creations(for: productID).allSatisfy({ [.ready, .saved].contains($0.status) }) else {
            alert = AppAlert(title: "先完成当前版本", message: "请继续已有版本，完成图文后再升级下一版。")
            return
        }
        operation = .working("正在创建内容版本")
        let versionNumber = (creations(for: productID).compactMap(\.versionNumber).max() ?? creations(for: productID).count) + 1
        let confirmedID = UUID()
        let creationID = UUID()
        let jobID = UUID()
        currentSnapshotID = confirmedID
        currentCreationID = creationID
        imageJobID = jobID
        let confirmed = makeProductSnapshot(id: confirmedID, productID: productID, confirmed: true)
        let creation = Creation(id: creationID, productSnapshotID: confirmedID, platform: .xiaohongshu, template: .handheldLifestyleV1, imageJobID: jobID, status: .generatingImage, createdAt: .now, updatedAt: .now, versionNumber: versionNumber, revisionNote: revisionNote.nilIfEmpty, isPreview: connectionState == .preview)
        let prompt = imagePrompt(for: confirmed, reviewIssues: [])
        let promptVersion = PromptVersion(id: UUID(), productSnapshotID: confirmedID, templateVersion: CreativeTemplate.handheldLifestyleV1.rawValue, prompt: prompt, negativeConstraints: confirmed.lockedFeatures, precedingReviewIssues: [], model: imageModelName, providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["ratio": "3:4", "count": "1"], createdAt: .now)
        let job = GenerationJob(id: jobID, kind: .image, creationID: creationID, idempotencyKey: UUID(), model: imageModelName, promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
        do {
            try await commit { state in
                state.productSnapshots.removeAll { $0.id == oldSnapshotID && !state.creations.contains(where: { $0.productSnapshotID == oldSnapshotID }) }
                state.productSnapshots.append(confirmed)
                if let index = state.products.firstIndex(where: { $0.id == productID }) {
                    state.products[index].currentSnapshotID = confirmedID
                    state.products[index].status = .creating
                }
                state.creations.append(creation)
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
            }
            screen = .imageGeneration
            imageGenerationTask = Task { await generateImage(prompt: prompt) }
        } catch { operation = .idle; alert = AppAlert.from(error) }
    }

    func generateImage(prompt: String? = nil, reviewIssues: [ReviewIssue] = []) async {
        guard let creationID = currentCreationID, let snapshotID = currentSnapshotID else { return }
        imageSubmissionAccepted = false
        screen = .imageGeneration
        operation = .working("正在准备参考图")
        do {
            if let imageJobID,
               snapshot.jobs.first(where: { $0.id == imageJobID })?.status == .draft {
                try await mutateJob(imageJobID, status: .submitting)
            }
            let activePrompt = promptForJob(imageJobID)
                ?? prompt
                ?? imagePrompt(for: currentProductSnapshot() ?? makeProductSnapshot(id: snapshotID, productID: currentProductID ?? UUID(), confirmed: true), reviewIssues: reviewIssues)
            if connectionState == .preview {
                if let imageJobID { try await mutateJob(imageJobID, status: .processing) }
                try await Task.sleep(for: .milliseconds(950))
                generatedImageAsset = sourceAssets.first
            } else {
                guard let provider, let assetStore else { throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用") }
                operation = .working("正在生成 3:4 生活方式画面")
                let result = try await provider.generateImage(.init(prompt: activePrompt, referenceImageURLs: await sourceURLs(), outputFormat: .png, idempotencyKey: jobIdempotencyKey(imageJobID ?? UUID()) ?? UUID()))
                imageSubmissionAccepted = true
                var asset: LocalAsset
                if let remoteURL = result.remoteURL {
                    if let imageJobID { try await recordImageResultURL(remoteURL, jobID: imageJobID) }
                    asset = try await assetStore.download(from: remoteURL, creationID: creationID, kind: .generatedImage, maximumBytes: configuration?.image.maximumDownloadBytes ?? 31_457_280, allowedMIMETypes: ["image/png", "image/jpeg", "image/heic"])
                } else if let base64 = result.base64 {
                    if let imageJobID { try await mutateJob(imageJobID, status: .downloading) }
                    asset = try await assetStore.storeBase64(
                        base64,
                        creationID: creationID,
                        mimeType: result.mimeType,
                        maximumBytes: configuration?.image.maximumDownloadBytes ?? 31_457_280
                    )
                } else {
                    throw AppError.safe("IMAGE_RESPONSE_INVALID", "图片生成结果不可用")
                }
                asset.productSnapshotID = snapshotID
                asset.promptVersionID = snapshot.jobs.first(where: { $0.id == imageJobID })?.promptVersionID
                generatedImageAsset = asset
                try await commit { state in state.assets.append(asset) }
            }
            if let jobID = imageJobID {
                if connectionState == .preview { try await mutateJob(jobID, status: .downloading) }
                try await mutateJob(jobID, status: .needsReview, outputAssetID: generatedImageAsset?.id)
            }
            operation = .idle
            selectedImageChecks = []
            screen = .imageReview
        } catch is CancellationError {
            if canRetryImageDownload {
                operation = .failed("图片结果地址已保留；回到前台后只会重新下载，不会重复生成。")
            } else {
                operation = .failed("已取消本机等待；供应商侧请求可能仍会完成。")
            }
        } catch {
            isImageSubmissionUnknown = isAmbiguousSubmissionError(error)
            operation = .failed(AppAlert.from(error).message)
            if canRetryImageDownload, (error as? AppError)?.code != "MEDIA_SPEC_INVALID" {
                await recordCurrentJobError(imageJobID, error: error)
            } else {
                await markCurrentJobFailed(imageJobID, error: error, submissionOutcomeUnknown: isImageSubmissionUnknown)
            }
        }
    }

    func approveImageAndGenerateVideo() async {
        guard imageReviewComplete, let creationID = currentCreationID, let imageAsset = generatedImageAsset else { return }
        let decision = ReviewDecision(id: UUID(), assetID: imageAsset.id, result: .approved, issueTypes: [], note: nil, createdAt: .now)
        let jobID = UUID()
        videoJobID = jobID
        let promptVersion = PromptVersion(id: UUID(), productSnapshotID: currentSnapshotID ?? UUID(), templateVersion: "handheld_motion_v1", prompt: videoPrompt(), negativeConstraints: ["商品不得形变", "不新增文字", "背景不跳变"], precedingReviewIssues: [], model: configuration?.models.video ?? "", providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["duration": videoSummary, "resolution": "720p", "audio": "false"], createdAt: .now)
        let job = GenerationJob(id: jobID, kind: .video, creationID: creationID, idempotencyKey: UUID(), model: configuration?.models.video ?? "", promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
        do {
            try await commit { state in
                state.reviews.append(decision)
                if let index = state.jobs.firstIndex(where: { $0.id == imageJobID }) { state.jobs[index].status = .succeeded }
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[index].videoJobID = jobID
                    state.creations[index].status = .generatingVideo
                    state.creations[index].updatedAt = .now
                }
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
            }
            videoGenerationTask?.cancel()
            videoGenerationTask = Task { await generateVideo() }
        } catch { alert = AppAlert.from(error) }
    }

    func rejectImage(issues: [ReviewIssue]) async {
        guard let asset = generatedImageAsset, !issues.isEmpty else { return }
        let oldJobID = imageJobID
        let newJobID = UUID()
        imageJobID = newJobID
        do {
            let decision = ReviewDecision(id: UUID(), assetID: asset.id, result: .rejected, issueTypes: issues, note: nil, createdAt: .now)
            guard let facts = currentProductSnapshot() else { throw AppError.safe("PRODUCT_FACT_REQUIRED", "请先确认商品关键信息") }
            let promptVersion = PromptVersion(id: UUID(), productSnapshotID: facts.id, templateVersion: CreativeTemplate.handheldLifestyleV1.rawValue, prompt: imagePrompt(for: facts, reviewIssues: issues), negativeConstraints: facts.lockedFeatures + issues.map(\.promptConstraint), precedingReviewIssues: issues, model: imageModelName, providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["ratio": "3:4", "count": "1"], createdAt: .now)
            let job = GenerationJob(id: newJobID, kind: .image, creationID: currentCreationID, idempotencyKey: UUID(), model: imageModelName, promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
            try await commit { state in
                state.reviews.append(decision)
                if let oldJobID, let index = state.jobs.firstIndex(where: { $0.id == oldJobID }) { state.jobs[index].status = .failed }
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
                if let creationID = currentCreationID, let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].imageJobID = newJobID }
            }
            imageGenerationTask?.cancel()
            imageGenerationTask = Task { await generateImage(reviewIssues: issues) }
        } catch { alert = AppAlert.from(error) }
    }

    func generateVideo() async {
        guard let creationID = currentCreationID, let imageAsset = generatedImageAsset, let videoJobID else { return }
        var submissionAccepted = false
        screen = .videoGeneration
        operation = .working("正在提交 AI 动态任务")
        do {
            if snapshot.jobs.first(where: { $0.id == videoJobID })?.status == .draft {
                try await mutateJob(videoJobID, status: .submitting)
            }
            if connectionState == .preview {
                try await Task.sleep(for: .milliseconds(950))
                try await mutateJob(videoJobID, status: .processing)
                try await mutateJob(videoJobID, status: .downloading)
                try await mutateJob(videoJobID, status: .needsReview)
                operation = .idle
                selectedVideoChecks = []
                screen = .videoReview
                return
            }
            guard let provider, let assetStore, let snapshotStore else { throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用") }
            let imageURL = try await assetStore.url(for: imageAsset)
            let activePrompt = promptForJob(videoJobID) ?? videoPrompt()
            let remote = try await provider.createVideo(.init(imageURL: imageURL, prompt: activePrompt, idempotencyKey: jobIdempotencyKey(videoJobID) ?? UUID()))
            submissionAccepted = true
            snapshot = try await snapshotStore.recordRemoteVideoTask(localJobID: videoJobID, providerTaskID: remote.taskID, status: remote.status == .queued ? .queued : .processing)
            operation = .working("AI 动态正在生成，可离开后继续")
            pollingTask?.cancel()
            pollingTask = Task { await pollVideo(taskID: remote.taskID, creationID: creationID, jobID: videoJobID) }
        } catch is CancellationError {
            if snapshot.jobs.first(where: { $0.id == videoJobID })?.providerTaskID == nil {
                isVideoSubmissionUnknown = true
                try? await mutateJob(videoJobID, status: .submissionUnknown)
                operation = .failed("已停止本机等待；动态提交结果未知，请只用原幂等键重试。")
            }
        } catch {
            isVideoSubmissionUnknown = submissionAccepted || isAmbiguousSubmissionError(error)
            operation = .failed(AppAlert.from(error).message)
            await markCurrentJobFailed(videoJobID, error: error, submissionOutcomeUnknown: isVideoSubmissionUnknown)
        }
    }

    func handleSceneBecameActive() {
        if screen == .imageGeneration, canRetryImageDownload {
            imageGenerationTask?.cancel()
            imageGenerationTask = Task { await retryImageDownload() }
            return
        }
        if screen == .videoGeneration, canRetryVideoDownload {
            pollingTask?.cancel()
            pollingTask = Task { await retryVideoDownload() }
            return
        }
        guard connectionState != .preview, let videoJobID,
              let job = snapshot.jobs.first(where: { $0.id == videoJobID }),
              let taskID = job.providerTaskID, job.status.shouldResume,
              let creationID = currentCreationID else { return }
        pollingTask?.cancel()
        pollingTask = Task { await pollVideo(taskID: taskID, creationID: creationID, jobID: videoJobID) }
    }

    func handleSceneEnteredBackground() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func handleSceneWillResignActive() {
        guard connectionState != .preview else { return }
        if screen == .imageGeneration, let imageJobID {
            if imageSubmissionAccepted,
               snapshot.jobs.first(where: { $0.id == imageJobID })?.providerResultURL == nil {
                return
            }
            imageGenerationTask?.cancel()
            imageGenerationTask = nil
            if let job = snapshot.jobs.first(where: { $0.id == imageJobID }), job.status == .downloading, job.providerResultURL != nil {
                operation = .failed("图片下载已暂停；回到前台后只会重新下载原结果。")
            } else if let job = snapshot.jobs.first(where: { $0.id == imageJobID }),
                      job.status == .submitting || job.status == .processing {
                Task {
                    try? await mutateJob(imageJobID, status: .submissionUnknown)
                    isImageSubmissionUnknown = true
                    operation = .failed("App 已中断等待，提交结果未知；返回后请用原幂等键重试。")
                }
            }
        } else if screen == .videoGeneration, let videoJobID,
                  let job = snapshot.jobs.first(where: { $0.id == videoJobID }),
                  job.status == .submitting, job.providerTaskID == nil {
            Task {
                try? await mutateJob(videoJobID, status: .submissionUnknown)
                isVideoSubmissionUnknown = true
                operation = .failed("App 已中断等待，动态提交结果未知；返回后请用原幂等键重试。")
            }
        }
    }

    func cancelCurrentGeneration() async {
        if screen == .imageGeneration {
            imageGenerationTask?.cancel()
            imageGenerationTask = nil
            if let imageJobID,
               let job = snapshot.jobs.first(where: { $0.id == imageJobID }),
               job.status == .draft {
                try? await mutateJob(imageJobID, status: .cancelled)
            } else if let imageJobID,
                      let job = snapshot.jobs.first(where: { $0.id == imageJobID }),
                      connectionState == .preview,
                      job.status == .submitting || job.status == .processing || job.status == .downloading {
                try? await mutateJob(imageJobID, status: .cancelled)
            } else if let imageJobID,
                      let job = snapshot.jobs.first(where: { $0.id == imageJobID }),
                      job.status == .submitting || job.status == .processing {
                try? await mutateJob(imageJobID, status: .submissionUnknown)
                isImageSubmissionUnknown = true
            }
            operation = canRetryImageDownload
                ? .failed("已停止本机下载；可继续下载原结果，不会重复生成。")
                : .failed("已取消本机等待；若请求已提交，供应商仍可能完成并产生费用。")
        } else if screen == .videoGeneration {
            if let videoJobID,
               let job = snapshot.jobs.first(where: { $0.id == videoJobID }),
               job.status == .submitting, job.providerTaskID == nil {
                try? await mutateJob(videoJobID, status: .submissionUnknown)
                isVideoSubmissionUnknown = true
                operation = .failed("已停止本机等待；动态提交结果未知，请只用原幂等键重试。")
            } else {
                pollingTask?.cancel()
                pollingTask = nil
                operation = .failed("已停止本机查询；远端动态任务可能仍在运行并产生费用，可稍后从记录继续。")
            }
        }
    }

    func retryUnknownImageSubmission() async {
        guard let imageJobID, let snapshotStore else { return }
        do {
            _ = try await snapshotStore.prepareIdempotentResubmission(localJobID: imageJobID)
            snapshot = try await snapshotStore.load()
            isImageSubmissionUnknown = false
            imageGenerationTask?.cancel()
            imageGenerationTask = Task { await generateImage() }
        } catch { alert = AppAlert.from(error) }
    }

    func retryImageDownload() async {
        guard let job = currentImageJob,
              let value = job.providerResultURL,
              let remoteURL = URL(string: value),
              let creationID = currentCreationID,
              let snapshotID = currentSnapshotID,
              let assetStore else { return }
        operation = .working("正在重新下载原图片结果")
        do {
            var asset = try await assetStore.download(
                from: remoteURL,
                creationID: creationID,
                kind: .generatedImage,
                maximumBytes: configuration?.image.maximumDownloadBytes ?? 31_457_280,
                allowedMIMETypes: ["image/png", "image/jpeg", "image/heic"]
            )
            asset.productSnapshotID = snapshotID
            asset.promptVersionID = job.promptVersionID
            generatedImageAsset = asset
            try await commit { state in
                state.assets.append(asset)
                guard let index = state.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                try JobStateMachine.transition(&state.jobs[index], to: .needsReview)
                state.jobs[index].outputAssetIDs = [asset.id]
                if let creationIndex = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[creationIndex].status = .imageReview
                    state.creations[creationIndex].updatedAt = .now
                }
            }
            operation = .idle
            selectedImageChecks = []
            screen = .imageReview
        } catch is CancellationError {
            operation = .failed("图片下载已暂停；稍后可继续下载原结果。")
        } catch {
            operation = .failed(AppAlert.from(error).message)
            if (error as? AppError)?.code == "MEDIA_SPEC_INVALID" {
                await markCurrentJobFailed(job.id, error: error)
            } else {
                await recordCurrentJobError(job.id, error: error)
            }
        }
    }

    func retryVideoDownload() async {
        guard let job = currentVideoJob,
              let value = job.providerResultURL,
              let resultURL = URL(string: value),
              let creationID = currentCreationID,
              let snapshotID = currentSnapshotID,
              let assetStore else { return }
        operation = .working("正在重新下载原动态结果")
        do {
            var asset = try await assetStore.download(
                from: resultURL,
                creationID: creationID,
                kind: .generatedVideo,
                maximumBytes: configuration?.video.maximumDownloadBytes ?? 209_715_200,
                allowedMIMETypes: ["video/mp4", "video/quicktime"]
            )
            asset.productSnapshotID = snapshotID
            asset.promptVersionID = job.promptVersionID
            generatedVideoAsset = asset
            try await commit { state in
                state.assets.append(asset)
                guard let index = state.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                try JobStateMachine.transition(&state.jobs[index], to: .needsReview)
                state.jobs[index].outputAssetIDs = [asset.id]
                if let creationIndex = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[creationIndex].status = .videoReview
                    state.creations[creationIndex].updatedAt = .now
                }
            }
            operation = .idle
            selectedVideoChecks = []
            screen = .videoReview
        } catch is CancellationError {
            operation = .failed("动态下载已暂停；稍后可继续下载原结果。")
        } catch {
            operation = .failed(AppAlert.from(error).message)
            if (error as? AppError)?.code == "MEDIA_SPEC_INVALID" {
                await markCurrentJobFailed(job.id, error: error)
            } else {
                await recordCurrentJobError(job.id, error: error)
            }
        }
    }

    func retryUnknownVideoSubmission() async {
        guard let videoJobID, let snapshotStore else { return }
        do {
            _ = try await snapshotStore.prepareIdempotentResubmission(localJobID: videoJobID)
            snapshot = try await snapshotStore.load()
            isVideoSubmissionUnknown = false
            videoGenerationTask?.cancel()
            videoGenerationTask = Task { await generateVideo() }
        } catch { alert = AppAlert.from(error) }
    }

    func retryFailedImageGeneration() async {
        guard canCreateReplacementImageJob, let facts = currentProductSnapshot(), let creationID = currentCreationID else { return }
        let newJobID = UUID()
        let promptVersion = PromptVersion(id: UUID(), productSnapshotID: facts.id, templateVersion: CreativeTemplate.handheldLifestyleV1.rawValue, prompt: imagePrompt(for: facts, reviewIssues: [.other]), negativeConstraints: facts.lockedFeatures + [ReviewIssue.other.promptConstraint], precedingReviewIssues: [.other], model: imageModelName, providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["ratio": "3:4", "count": "1"], createdAt: .now)
        let job = GenerationJob(id: newJobID, kind: .image, creationID: creationID, idempotencyKey: UUID(), model: imageModelName, promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
        do {
            try await commit { state in
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[index].imageJobID = newJobID
                    state.creations[index].status = .generatingImage
                    state.creations[index].updatedAt = .now
                }
            }
            imageJobID = newJobID
            imageGenerationTask?.cancel()
            imageGenerationTask = Task { await generateImage(reviewIssues: [.other]) }
        } catch { alert = AppAlert.from(error) }
    }

    func retryFailedVideoGeneration() async {
        guard canCreateReplacementVideoJob, generatedImageAsset != nil, let snapshotID = currentSnapshotID, let creationID = currentCreationID else { return }
        let newJobID = UUID()
        let promptVersion = PromptVersion(id: UUID(), productSnapshotID: snapshotID, templateVersion: "handheld_motion_v1", prompt: videoPrompt() + " 返修约束：修正上一次供应商失败。", negativeConstraints: [ReviewIssue.other.promptConstraint], precedingReviewIssues: [.other], model: configuration?.models.video ?? "", providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["duration": videoSummary, "resolution": "720p", "audio": "false"], createdAt: .now)
        let job = GenerationJob(id: newJobID, kind: .video, creationID: creationID, idempotencyKey: UUID(), model: configuration?.models.video ?? "", promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
        do {
            try await commit { state in
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[index].videoJobID = newJobID
                    state.creations[index].status = .generatingVideo
                    state.creations[index].updatedAt = .now
                }
            }
            videoJobID = newJobID
            videoGenerationTask?.cancel()
            videoGenerationTask = Task { await generateVideo() }
        } catch { alert = AppAlert.from(error) }
    }

    func retryCopyGeneration() async {
        await approveVideoAndGenerateCopy()
    }

    func approveImageAndGenerateCopy() async {
        await approveVideoAndGenerateCopy()
    }

    func approveVideoAndGenerateCopy() async {
        guard !isWorking, requireAIService(), (videoJobID == nil ? imageReviewComplete : videoReviewComplete), let creationID = currentCreationID, let asset = generatedVideoAsset ?? generatedImageAsset else { return }
        let decision = ReviewDecision(id: UUID(), assetID: asset.id, result: .approved, issueTypes: [], note: nil, createdAt: .now)
        let copyJobID = UUID()
        let job = GenerationJob(id: copyJobID, kind: .copy, creationID: creationID, idempotencyKey: UUID(), model: configuration?.models.text ?? "", status: .processing, outputAssetIDs: [])
        operation = .working("正在生成小红书文案")
        do {
            try await commit { state in
                state.reviews.append(decision)
                if let reviewJobID = videoJobID ?? imageJobID, let index = state.jobs.firstIndex(where: { $0.id == reviewJobID }) { state.jobs[index].status = .succeeded }
                state.jobs.append(job)
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) {
                    state.creations[index].copyJobID = copyJobID
                    state.creations[index].status = .generatingCopy
                    state.creations[index].updatedAt = .now
                }
            }
            let draft: CopyPackageDraft
            if connectionState == .preview {
                try await Task.sleep(for: .milliseconds(700))
                draft = CopyPackageDraft(
                    titles: ["最近很喜欢的\(productName)", "把日常过得更有仪式感", "一眼心动的生活小物"],
                    body: "最近在整理日常好物时，注意到这件\(productName)。\n\n\(sellingPoint)。画面里的颜色与细节以真实商品为准，发布前也记得再核对一次商品信息。",
                    topics: ["家居好物", "生活仪式感", "好物分享", "小红书种草", "日常生活", "实用好物", "生活灵感", "商品分享"], factClaims: [], warnings: ["AI 内容，请核对商品事实"]
                )
            } else {
                guard let provider, let facts = currentProductSnapshot() else { throw AppError.safe("PRODUCT_FACT_REQUIRED", "请先确认商品关键信息") }
                draft = try await provider.generateCopy(.init(facts: facts, creativeSummary: "真人手持生活方式，3:4，自然光。版本优化方向：\(revisionNote)", prohibitedClaims: ["虚构购买经历", "价格", "疗效", "权威背书", "未经确认的评价"], idempotencyKey: UUID()))
            }
            copyTitles = draft.titles
            copyBody = draft.body
            copyTopics = draft.topics
            selectedTitleIndex = 0
            let stored = StoredCopyPackage(id: UUID(), creationID: creationID, titles: draft.titles, selectedTitleIndex: 0, body: draft.body, topics: draft.topics, createdAt: .now, updatedAt: .now)
            try await commit { state in
                state.copyPackages.removeAll { $0.creationID == creationID }
                state.copyPackages.append(stored)
                if let index = state.jobs.firstIndex(where: { $0.id == copyJobID }) { state.jobs[index].status = .succeeded }
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].status = .ready; state.creations[index].updatedAt = .now }
            }
            operation = .idle
            screen = .copyResult
        } catch {
            operation = .failed(AppAlert.from(error).message)
        }
    }

    func rejectVideo(issues: [ReviewIssue]) async {
        guard let asset = generatedVideoAsset ?? generatedImageAsset, !issues.isEmpty else { return }
        let oldJobID = videoJobID
        let newJobID = UUID()
        videoJobID = newJobID
        do {
            let decision = ReviewDecision(id: UUID(), assetID: asset.id, result: .rejected, issueTypes: issues, note: nil, createdAt: .now)
            let promptVersion = PromptVersion(id: UUID(), productSnapshotID: currentSnapshotID ?? UUID(), templateVersion: "handheld_motion_v1", prompt: videoPrompt() + " 返修约束：" + issues.map(\.promptConstraint).joined(separator: "；"), negativeConstraints: issues.map(\.promptConstraint), precedingReviewIssues: issues, model: configuration?.models.video ?? "", providerSchemaVersion: configuration?.schemaVersion ?? 1, parameters: ["duration": videoSummary, "resolution": "720p", "audio": "false"], createdAt: .now)
            let job = GenerationJob(id: newJobID, kind: .video, creationID: currentCreationID, idempotencyKey: UUID(), model: configuration?.models.video ?? "", promptVersionID: promptVersion.id, status: .draft, outputAssetIDs: [])
            try await commit { state in
                state.reviews.append(decision)
                if let oldJobID, let index = state.jobs.firstIndex(where: { $0.id == oldJobID }) { state.jobs[index].status = .failed }
                state.promptVersions.append(promptVersion)
                state.jobs.append(job)
                if let creationID = currentCreationID, let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].videoJobID = newJobID }
            }
            videoGenerationTask?.cancel()
            videoGenerationTask = Task { await generateVideo() }
        } catch { alert = AppAlert.from(error) }
    }

    func confirmCopy() async {
        guard let creationID = currentCreationID else { return }
        if isCurrentVersionReadOnly { screen = .saveResult; return }
        do {
            try await commit { state in
                if let index = state.copyPackages.firstIndex(where: { $0.creationID == creationID }) {
                    state.copyPackages[index].titles = copyTitles
                    state.copyPackages[index].selectedTitleIndex = selectedTitleIndex
                    state.copyPackages[index].body = copyBody
                    state.copyPackages[index].topics = copyTopics
                    state.copyPackages[index].updatedAt = .now
                }
            }
            screen = .saveResult
        } catch { alert = AppAlert.from(error) }
    }

    func copyTextToClipboard() async {
        guard copyTitles.indices.contains(selectedTitleIndex) else { return }
        let text = ([copyTitles[selectedTitleIndex], copyBody] + copyTopics.map { "#\($0.replacingOccurrences(of: "#", with: ""))" }).joined(separator: "\n\n")
        UIPasteboard.general.string = text
        await updateExport(copyStatus: .saved)
    }

    func saveAllMedia() async {
        guard hasRealGeneratedMedia, let image = generatedImageAsset, let video = generatedVideoAsset,
              let assetStore, let creationID = currentCreationID else {
            alert = AppAlert(title: "预览模式不写入相册", message: "当前只展示交互流程，没有真实生成媒体。填入有效供应商配置并完成真实生成后，才可保存 Live Photo、MP4 和静态图。")
            return
        }
        operation = .working("正在保存内容包")
        let imageURL: URL
        let videoURL: URL
        do {
            imageURL = try await assetStore.url(for: image)
            videoURL = try await assetStore.url(for: video)
        } catch {
            operation = .failed(AppAlert.from(error).message)
            return
        }

        var record = exportRecord ?? ExportRecord(id: UUID(), creationID: creationID, livePhotoStatus: .notRequested, imageStatus: .notRequested, videoStatus: .notRequested, copyStatus: .notRequested, createdAt: .now, updatedAt: .now)
        record.livePhotoStatus = .saving; record.imageStatus = .saving; record.videoStatus = .saving
        exportRecord = record

        do {
            let result = try await photoLibrary.saveImage(at: imageURL)
            record.imageStatus = .saved; record.imageLocalIdentifier = result.localIdentifier
        } catch {
            record.imageStatus = .failed
            if (error as? AppError)?.code == "SAVE_PERMISSION_DENIED" {
                alert = AppAlert(title: "需要相册权限", message: "请在系统设置中允许 Muses 添加照片；已有生成结果不会丢失。")
            }
        }
        do {
            let result = try await photoLibrary.saveVideo(at: videoURL)
            record.videoStatus = .saved; record.videoLocalIdentifier = result.localIdentifier
        } catch { record.videoStatus = .failed }
        do {
            guard let livePhotoService else { throw AppError.safe("LIVE_PHOTO_PACKAGE_FAILED", "实况照片生成失败，MP4仍可保存") }
            let result = try await livePhotoService.createAndSave(photoURL: imageURL, videoURL: videoURL)
            record.livePhotoStatus = .saved; record.livePhotoLocalIdentifier = result.localIdentifier
        } catch {
            record.livePhotoStatus = .failed
            if (error as? AppError)?.code != "SAVE_PERMISSION_DENIED" {
                alert = AppAlert(title: "实况照片未保存", message: "实况封装失败，但静态图、MP4 与文案仍可单独使用。")
            }
        }
        record.updatedAt = .now
        exportRecord = record
        let hasUsableMedia = record.imageStatus == .saved || record.videoStatus == .saved || record.livePhotoStatus == .saved
        do {
            try await commit { state in
                state.exportRecords.removeAll { $0.creationID == creationID }
                state.exportRecords.append(record)
                if hasUsableMedia, let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].status = .saved; state.creations[index].updatedAt = .now }
                if hasUsableMedia, let productID = currentProductID, let index = state.products.firstIndex(where: { $0.id == productID }) { state.products[index].status = .completed }
            }
        } catch { alert = AppAlert.from(error) }
        operation = .idle
    }

    func openXiaohongshu() async {
        guard let url = URL(string: "xhsdiscover://") else { return }
        let opened = await UIApplication.shared.open(url)
        if !opened { alert = AppAlert(title: "无法打开小红书", message: "请手动打开小红书，并从相册选择已保存内容完成发布。") }
    }

    func openSystemSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        _ = await UIApplication.shared.open(url)
    }

    func resume(product: Product, creation requestedCreation: Creation? = nil) async {
        guard !isWorking else { return }
        startNewProduct()
        currentProductID = product.id
        let targetSnapshotID = requestedCreation?.productSnapshotID ?? product.currentSnapshotID
        currentSnapshotID = targetSnapshotID
        productName = product.name
        sku = product.sku ?? ""
        guard let facts = snapshot.productSnapshots.first(where: { $0.id == targetSnapshotID }) else { return }
        sourceAssets = facts.sourceAssetIDs.compactMap { id in snapshot.assets.first(where: { $0.id == id }) }
        load(facts: facts)
        guard let creation = requestedCreation ?? creations(for: product.id).last else {
            screen = product.status == .factsPending ? .factConfirmation : .product
            return
        }
        currentCreationID = creation.id
        revisionNote = creation.revisionNote ?? ""
        if creation.isPreview == true { connectionState = .preview }
        else if connectionState == .preview { connectionState = .idle }
        imageJobID = creation.imageJobID
        videoJobID = creation.videoJobID
        generatedImageAsset = creation.imageJobID.flatMap { id in snapshot.jobs.first(where: { $0.id == id })?.outputAssetIDs.first }.flatMap { id in snapshot.assets.first(where: { $0.id == id }) }
        generatedVideoAsset = creation.videoJobID.flatMap { id in snapshot.jobs.first(where: { $0.id == id })?.outputAssetIDs.first }.flatMap { id in snapshot.assets.first(where: { $0.id == id }) }
        selectedImageChecks = Set(imageReviewItems.filter { _ in snapshot.reviews.contains { $0.assetID == generatedImageAsset?.id && $0.result == .approved } })
        selectedVideoChecks = Set(videoReviewItems.filter { _ in snapshot.reviews.contains { $0.assetID == generatedVideoAsset?.id && $0.result == .approved } })
        if let stored = snapshot.copyPackages.first(where: { $0.creationID == creation.id }) {
            copyTitles = stored.titles; selectedTitleIndex = stored.selectedTitleIndex; copyBody = stored.body; copyTopics = stored.topics
        }
        exportRecord = snapshot.exportRecords.first(where: { $0.creationID == creation.id })
        switch creation.status {
        case .draft: screen = .factConfirmation
        case .generatingImage: screen = .imageGeneration
        case .imageReview: screen = .imageReview
        case .generatingVideo: screen = .videoGeneration; handleSceneBecameActive()
        case .videoReview: screen = .videoReview
        case .generatingCopy:
            screen = videoJobID == nil ? .imageReview : .videoReview
            operation = .failed("文案生成未完成，可重试文案生成。")
        case .ready: screen = .copyResult
        case .saved: screen = .saveResult
        case .failed: screen = .history
        }
        if let videoJobID,
           snapshot.jobs.first(where: { $0.id == videoJobID })?.status == .submissionUnknown {
            screen = .videoGeneration
            isVideoSubmissionUnknown = true
            operation = .failed("上次动态提交结果未知；仅可使用原幂等键重试，避免重复扣费。")
        } else if let imageJobID, snapshot.jobs.first(where: { $0.id == imageJobID })?.status == .submissionUnknown {
            screen = .imageGeneration
            isImageSubmissionUnknown = true
            operation = .failed("上次图片提交结果未知；仅可使用原幂等键重试。")
        } else if canRetryVideoDownload {
            screen = .videoGeneration
            operation = .failed("动态生成已完成，但本地结果尚未下载；继续时不会重复生成。")
        } else if canRetryImageDownload {
            screen = .imageGeneration
            operation = .failed("图片生成已完成，但本地结果尚未下载；继续时不会重复生成。")
        } else if let imageJobID,
                  let job = snapshot.jobs.first(where: { $0.id == imageJobID }),
                  job.status == .failed {
            screen = .imageGeneration
            operation = .failed(job.safeErrorMessage ?? "图片生成失败，可创建新任务重试。")
        } else if let videoJobID,
                  let job = snapshot.jobs.first(where: { $0.id == videoJobID }),
                  job.status == .failed {
            screen = .videoGeneration
            operation = .failed(job.safeErrorMessage ?? "动态生成失败，图片仍已保留。")
        }
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

    private func pollVideo(taskID: String, creationID: MusesID, jobID: MusesID) async {
        guard let provider, let assetStore else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(configuration?.video.maxPollDurationMs ?? 900_000) / 1_000)
        do {
            while !Task.isCancelled && Date() < deadline {
                let status = try await provider.getVideoJob(taskID: taskID)
                switch status.status {
                case .queued, .processing:
                    try await mutateJob(jobID, status: status.status == .queued ? .queued : .processing)
                    try await Task.sleep(for: .milliseconds(configuration?.video.pollIntervalMs ?? 5_000))
                case .succeeded:
                    guard let resultURL = status.resultURL else { throw AppError.safe("ASSET_DOWNLOAD_FAILED", "动态已生成，但结果地址不可用", retryable: true) }
                    operation = .working("动态已生成，正在下载")
                    try await recordVideoResultURL(resultURL, jobID: jobID)
                    var asset = try await assetStore.download(from: resultURL, creationID: creationID, kind: .generatedVideo, maximumBytes: configuration?.video.maximumDownloadBytes ?? 209_715_200, allowedMIMETypes: ["video/mp4", "video/quicktime"])
                    asset.productSnapshotID = currentSnapshotID
                    asset.promptVersionID = snapshot.jobs.first(where: { $0.id == jobID })?.promptVersionID
                    generatedVideoAsset = asset
                    try await commit { state in
                        state.assets.append(asset)
                        if let index = state.jobs.firstIndex(where: { $0.id == jobID }) { state.jobs[index].status = .needsReview; state.jobs[index].outputAssetIDs = [asset.id] }
                        if let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].status = .videoReview; state.creations[index].updatedAt = .now }
                    }
                    operation = .idle
                    selectedVideoChecks = []
                    screen = .videoReview
                    return
                case .failed:
                    try await mutateJob(jobID, status: .failed)
                    operation = .failed(status.safeError ?? "AI 动态生成失败，图片仍已保留")
                    return
                case .cancelled:
                    try await mutateJob(jobID, status: .cancelled)
                    operation = .failed("供应商已取消动态任务")
                    return
                case .unknown:
                    try await mutateJob(jobID, status: .unknown)
                    operation = .working("暂时无法确认动态任务状态，稍后将继续查询")
                    try await Task.sleep(for: .milliseconds(configuration?.video.pollIntervalMs ?? 5_000))
                }
            }
            try await mutateJob(jobID, status: .unknown)
            operation = .failed("暂时无法确认动态任务状态，可稍后继续查询")
        } catch is CancellationError {
            return
        } catch {
            operation = .failed(AppAlert.from(error).message)
            if (error as? AppError)?.code == "MEDIA_SPEC_INVALID" {
                await markCurrentJobFailed(jobID, error: error)
            } else {
                await markCurrentJobFailed(jobID, error: error, onlyIfDefinitive: false)
            }
        }
    }

    private func mutateJob(_ id: MusesID, status: JobStatus, outputAssetID: MusesID? = nil) async throws {
        try await commit { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == id }) else { return }
            try JobStateMachine.transition(&state.jobs[index], to: status)
            state.jobs[index].lastPolledAt = .now
            if let outputAssetID { state.jobs[index].outputAssetIDs = [outputAssetID] }
            if let creationID = currentCreationID, let creationIndex = state.creations.firstIndex(where: { $0.id == creationID }) {
                if status == .needsReview { state.creations[creationIndex].status = state.jobs[index].kind == .image ? .imageReview : .videoReview }
                state.creations[creationIndex].updatedAt = .now
            }
        }
    }

    private func markCurrentJobFailed(_ id: MusesID?, error: Error, onlyIfDefinitive: Bool = true, submissionOutcomeUnknown: Bool = false) async {
        guard let id else { return }
        let appError = AppAlert.from(error)
        let ambiguous = submissionOutcomeUnknown || isAmbiguousSubmissionError(error)
        let status: JobStatus = onlyIfDefinitive ? (ambiguous ? .submissionUnknown : .failed) : .unknown
        try? await commit { state in
            if let index = state.jobs.firstIndex(where: { $0.id == id }) {
                if JobStateMachine.canTransition(from: state.jobs[index].status, to: status) {
                    try JobStateMachine.transition(&state.jobs[index], to: status)
                }
                state.jobs[index].errorCode = (error as? AppError)?.code
                state.jobs[index].safeErrorMessage = appError.message
            }
        }
    }

    private func recordCurrentJobError(_ id: MusesID?, error: Error) async {
        guard let id else { return }
        let message = AppAlert.from(error).message
        try? await commit { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == id }) else { return }
            state.jobs[index].errorCode = (error as? AppError)?.code
            state.jobs[index].safeErrorMessage = message
        }
    }

    private func recordImageResultURL(_ url: URL, jobID: MusesID) async throws {
        try await commit { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == jobID }) else {
                throw AppError.safe("JOB_NOT_FOUND", "找不到图片生成任务")
            }
            state.jobs[index].providerResultURL = url.absoluteString
            try JobStateMachine.transition(&state.jobs[index], to: .downloading)
        }
    }

    private func recordVideoResultURL(_ url: URL, jobID: MusesID) async throws {
        try await commit { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == jobID }) else {
                throw AppError.safe("JOB_NOT_FOUND", "找不到动态生成任务")
            }
            state.jobs[index].providerResultURL = url.absoluteString
            try JobStateMachine.transition(&state.jobs[index], to: .downloading)
        }
    }

    private func updateExport(copyStatus: ExportItemStatus) async {
        guard let creationID = currentCreationID else { return }
        var record = exportRecord ?? ExportRecord(id: UUID(), creationID: creationID, livePhotoStatus: .notRequested, imageStatus: .notRequested, videoStatus: .notRequested, copyStatus: .notRequested, createdAt: .now, updatedAt: .now)
        record.copyStatus = copyStatus
        record.updatedAt = .now
        exportRecord = record
        try? await commit { state in
            state.exportRecords.removeAll { $0.creationID == creationID }
            state.exportRecords.append(record)
        }
    }

    private func commit(_ mutation: (inout AppSnapshot) throws -> Void) async throws {
        guard let snapshotStore else { throw AppError.safe("PERSISTENCE_UNAVAILABLE", "本地存储不可用") }
        var updated = snapshot
        try mutation(&updated)
        updated.updatedAt = .now
        try await snapshotStore.save(updated)
        snapshot = updated
    }

    private func sourceURLs() async -> [URL] {
        guard let assetStore else { return [] }
        var urls: [URL] = []
        for asset in sourceAssets {
            if let url = try? await assetStore.url(for: asset) { urls.append(url) }
        }
        return urls
    }

    private func makeProductSnapshot(id: MusesID, productID: MusesID, confirmed: Bool) -> ProductSnapshot {
        ProductSnapshot(
            id: id, productID: productID, sourceAssetIDs: sourceAssets.map(\.id),
            category: category.nilIfEmpty, material: material.nilIfEmpty, specification: specification.nilIfEmpty,
            colors: colorsText.componentsList, visiblePatterns: patternsText.componentsList, visibleText: visibleText.componentsList,
            audience: audience.nilIfEmpty, verifiedSellingPoints: [sellingPoint].filter { !$0.trimmed.isEmpty },
            lockedFeatures: lockedFeaturesText.componentsList, uncertainFields: uncertainFields,
            rightsConfirmed: rightsConfirmed, confirmedAt: confirmed ? .now : nil,
            fieldConfirmations: Dictionary(uniqueKeysWithValues: factConfirmationStates.map { ($0.key.rawValue, $0.value) })
        )
    }

    private func currentProductSnapshot() -> ProductSnapshot? {
        guard let id = currentSnapshotID else { return nil }
        return snapshot.productSnapshots.first { $0.id == id }
    }

    private func load(facts: ProductSnapshot) {
        category = facts.category ?? ""; material = facts.material ?? ""; specification = facts.specification ?? ""
        colorsText = facts.colors.joined(separator: "、"); patternsText = facts.visiblePatterns.joined(separator: "、"); visibleText = facts.visibleText.joined(separator: "、")
        audience = facts.audience ?? ""; sellingPoint = facts.verifiedSellingPoints.first ?? ""; lockedFeaturesText = facts.lockedFeatures.joined(separator: "、")
        uncertainFields = facts.uncertainFields; rightsConfirmed = facts.rightsConfirmed
        if let stored = facts.fieldConfirmations {
            factConfirmationStates = Dictionary(uniqueKeysWithValues: stored.compactMap { element in
                FactField(rawValue: element.key).map { ($0, element.value) }
            })
        } else if facts.confirmedAt != nil {
            factConfirmationStates = Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0, .confirmed) })
        } else {
            factConfirmationStates = Dictionary(uniqueKeysWithValues: FactField.allCases.map { ($0, .pending) })
            factConfirmationStates[.sellingPoint] = .confirmed
        }
    }

    func factStatus(for field: FactField) -> FactConfirmationStatus {
        factConfirmationStates[field] ?? .pending
    }

    func setFactStatus(_ status: FactConfirmationStatus, for field: FactField) {
        factConfirmationStates[field] = status
    }

    func markFactEdited(_ field: FactField, value: String) {
        factConfirmationStates[field] = isUsableConfirmedValue(value) ? .confirmed : .pending
    }

    func canConfirmFact(_ field: FactField) -> Bool {
        isUsableConfirmedValue(factValue(for: field))
    }

    private func imagePrompt(for facts: ProductSnapshot, reviewIssues: [ReviewIssue]) -> String {
        let factSummary = "材质：\(facts.material ?? "不确定")；颜色：\(facts.colors.joined(separator: "、"))；图案：\(facts.visiblePatterns.joined(separator: "、"))；文字：\(facts.visibleText.joined(separator: "、"))；规格：\(facts.specification ?? "不确定")"
        let constraints = (facts.lockedFeatures + reviewIssues.map(\.promptConstraint)).joined(separator: "；")
        return "本版本优化方向：\(revisionNote)。真人自然手持商品的日常生活方式摄影，柔和自然光，小红书 3:4 竖图，商品是唯一视觉主体，不过度精修。商品事实：\(factSummary)。禁止改变：\(constraints)；不增加配件、赠品、错误文字或虚构效果。"
    }

    private func videoPrompt() -> String {
        "在已审核图片基础上做轻微自然动作和缓慢镜头推近。保持商品本体、图案、文字、材质完全稳定；手部接触自然；背景不跳变；不新增文字；静音。"
    }

    private func jobIdempotencyKey(_ id: MusesID) -> UUID? { snapshot.jobs.first(where: { $0.id == id })?.idempotencyKey }

    private func isAmbiguousSubmissionError(_ error: Error) -> Bool {
        guard let code = (error as? AppError)?.code else { return false }
        return code == "REQUEST_TIMEOUT" || code == "NETWORK_FAILED"
    }

    private var currentImageJob: GenerationJob? { imageJobID.flatMap { id in snapshot.jobs.first { $0.id == id } } }
    private var currentVideoJob: GenerationJob? { videoJobID.flatMap { id in snapshot.jobs.first { $0.id == id } } }

    private func promptForJob(_ id: MusesID?) -> String? {
        guard let id,
              let versionID = snapshot.jobs.first(where: { $0.id == id })?.promptVersionID else { return nil }
        return snapshot.promptVersions.first(where: { $0.id == versionID })?.prompt
    }

    private func factValue(for field: FactField) -> String {
        switch field {
        case .category: category
        case .material: material
        case .specification: specification
        case .colors: colorsText
        case .patterns: patternsText
        case .visibleText: visibleText
        case .audience: audience
        case .sellingPoint: sellingPoint
        case .lockedFeatures: lockedFeaturesText
        }
    }

    private func isUsableConfirmedValue(_ value: String) -> Bool {
        let normalized = value.trimmed
        return !normalized.isEmpty && normalized != "待确认" && normalized != "以实物图为准"
    }

}

extension AppModel {
    var isWorking: Bool {
        if case .working = operation { return true }
        return false
    }

    var activeProduct: Product? { snapshot.products.first { $0.id == currentProductID } }
    var activeCreation: Creation? { snapshot.creations.first { $0.id == currentCreationID } }
    var isCurrentVersionReadOnly: Bool {
        guard let creation = activeCreation, let productID = currentProductID else { return false }
        return creation.tracking != nil || creations(for: productID).last?.id != creation.id
    }

    func selectTab(_ tab: MTab) {
        guard !isWorking else { return }
        if tab == .publish {
            screen = .history
            isQuickPublishPresented = true
        } else {
            selectedTab = tab
            screen = tab == .settings ? .setup : .history
            isQuickPublishPresented = false
        }
    }

    func dismissQuickPublish() {
        guard !isWorking else { return }
        screen = selectedTab == .settings ? .setup : .history
        isQuickPublishPresented = false
    }

    func showProduct(_ product: Product) {
        guard !isWorking else { return }
        screen = .productDetail(product.id)
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

    func requireAIService() -> Bool {
        if connectionState == .preview { return true }
        guard !isPlaceholderConfiguration, hasStoredCredential, provider != nil else {
            alert = AppAlert(title: "生成前需连接 AI 服务", message: "商品录入和数据跟进可直接使用。请到「个人设置」配置 AI 服务后，再回到此商品继续生成。")
            return false
        }
        return true
    }

    @discardableResult
    func saveProductDraft(navigate: Bool = true) async -> Bool {
        guard !isWorking, let productID = currentProductID else { return false }
        guard !sku.trimmed.isEmpty, !productName.trimmed.isEmpty, !sellingPoint.trimmed.isEmpty else {
            alert = AppAlert(title: "补全商品资料", message: "请填写 SKU、商品名称和真实卖点，图片可稍后补充。")
            return false
        }
        guard !snapshot.products.contains(where: { $0.id != productID && $0.sku?.lowercased() == sku.trimmed.lowercased() }) else {
            alert = AppAlert(title: "SKU 已存在", message: "请打开已有商品，或使用不同的 SKU 编号。")
            return false
        }
        operation = .working("正在保存商品")
        defer { operation = .idle }
        let snapshotID = UUID()
        let facts = makeProductSnapshot(id: snapshotID, productID: productID, confirmed: false)
        let product = Product(id: productID, name: productName.trimmed, createdAt: activeProduct?.createdAt ?? .now, currentSnapshotID: snapshotID, status: .draft, sku: sku.trimmed)
        do {
            try await commit { state in
                state.products.removeAll { $0.id == productID }
                state.products.append(product)
                state.productSnapshots.append(facts)
                state.assets.append(contentsOf: sourceAssets.filter { asset in !state.assets.contains { $0.id == asset.id } })
            }
            currentSnapshotID = snapshotID
            if navigate { screen = .productDetail(productID) }
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
                alert = AppAlert(title: "已导入 \(rows.count) 个 SKU", message: "打开商品后补充真实商品图，即可开始生成图文版本。")
                return
            }
            throw AppError.safe("SKU_DUPLICATE", "SKU「\(duplicate.sku)」已存在。本次未导入，请修改文件后重试。")
        } catch { alert = AppAlert.from(error) }
    }

    func prepareNextVersion(for product: Product) async {
        guard !isWorking else { return }
        let versions = creations(for: product.id)
        guard versions.allSatisfy({ [.ready, .saved].contains($0.status) }) else {
            if let unfinished = versions.last(where: { ![.ready, .saved].contains($0.status) }) {
                await resume(product: product, creation: unfinished)
            }
            return
        }
        let desiredMode = connectionState
        await resume(product: product)
        connectionState = desiredMode
        currentCreationID = nil
        imageJobID = nil
        videoJobID = nil
        generatedImageAsset = nil
        generatedVideoAsset = nil
        copyTitles = []; copyBody = ""; copyTopics = []; exportRecord = nil
        revisionNote = ""
        selectedImageChecks = []; selectedVideoChecks = []
        screen = currentProductSnapshot()?.confirmedAt == nil ? .product : .factConfirmation
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

    func saveStaticImage() async {
        guard !isWorking, let image = generatedImageAsset, image.kind == .generatedImage,
              let assetStore, let creationID = currentCreationID else { return }
        operation = .working("正在保存图片")
        defer { operation = .idle }
        do {
            let result = try await photoLibrary.saveImage(at: assetStore.url(for: image))
            var record = exportRecord ?? ExportRecord(id: UUID(), creationID: creationID, livePhotoStatus: .notRequested, imageStatus: .notRequested, videoStatus: .notRequested, copyStatus: .notRequested, createdAt: .now, updatedAt: .now)
            record.imageStatus = .saved
            record.imageLocalIdentifier = result.localIdentifier
            record.updatedAt = .now
            try await commit { state in
                state.exportRecords.removeAll { $0.creationID == creationID }
                state.exportRecords.append(record)
                if let index = state.creations.firstIndex(where: { $0.id == creationID }) { state.creations[index].status = .saved }
                if let index = state.products.firstIndex(where: { $0.id == currentProductID }) { state.products[index].status = .completed }
            }
            exportRecord = record
        } catch { alert = AppAlert.from(error) }
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

extension ReviewIssue {
    var promptConstraint: String {
        switch self {
        case .shapeChanged: "严格保持商品外形轮廓和比例"
        case .wrongColor: "严格保持真实颜色和透明度"
        case .wrongPattern: "严格保持图案数量、位置和纹理"
        case .wrongText: "不得改写或新增商品文字"
        case .wrongMaterial: "严格保持真实材质质感"
        case .addedObject: "不得新增部件、配件或赠品"
        case .deformation: "运动中商品不得形变、融化或闪烁"
        case .abnormalContact: "保持手与商品接触自然"
        case .backgroundJump: "保持背景连续稳定"
        case .other: "修正用户指出的其他一致性问题"
        }
    }

    var label: String {
        switch self {
        case .shapeChanged: "外形改变"; case .wrongColor: "颜色错误"; case .wrongPattern: "图案错误"
        case .wrongText: "文字错误"; case .wrongMaterial: "材质错误"; case .addedObject: "增加物品"
        case .deformation: "动态形变"; case .abnormalContact: "接触异常"; case .backgroundJump: "背景跳变"; case .other: "其他"
        }
    }
}
