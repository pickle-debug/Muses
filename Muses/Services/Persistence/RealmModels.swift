import Foundation
import RealmSwift

// MARK: - Saved data

final class Setting: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String = "default"

    // 个人信息
    @Persisted var nickname: String = ""
    @Persisted var introduction: String = ""

    // ponytail: 单用户、单套默认偏好；需要管理多个店铺时再拆 Store。
    @Persisted var shopName: String = ""
    @Persisted var shopCategory: String = ""
    @Persisted var targetAudience: String = ""
    @Persisted var brandTone: String = "真实、自然、可信"

    // 文案和媒体偏好
    @Persisted var writingStyle: String = "真实分享"
    @Persisted var writingNotes: String = ""
    @Persisted var bannedWords: List<String>
    @Persisted var imageStyle: String = "自然生活方式"
    @Persisted var videoStyle: String = "轻微自然动作"
    @Persisted var promptAppendix: String = ""

    // 仅在旧 JSON 数据和此标记一起成功提交后赋值。
    @Persisted var legacyImportedAt: Date?
    @Persisted var updatedAt: Date = .now
}

final class SKU: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: UUID = UUID()
    @Persisted(indexed: true) var code: String = ""
    @Persisted var name: String = ""

    // 用户输入的事实，作为 AI 识别和文案生成的输入
    @Persisted var sellingPoint: String = ""
    @Persisted var category: String?
    @Persisted var material: String?
    @Persisted var specification: String?
    @Persisted var colors: List<String>
    @Persisted var patterns: List<String>
    @Persisted var lockedFeatures: List<String>
    @Persisted var imagePaths: List<String>

    @Persisted var status: String = "draft"
    @Persisted var createdAt: Date = .now
    @Persisted var updatedAt: Date = .now

    convenience init(code: String, name: String, sellingPoint: String) {
        self.init()
        self.code = code
        self.name = name
        self.sellingPoint = sellingPoint
    }
}

final class Post: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: UUID = UUID()
    @Persisted(indexed: true) var skuID: UUID

    @Persisted var status: String = "draft"
    @Persisted var titles: List<String>
    @Persisted var selectedTitleIndex: Int = 0
    @Persisted var body: String = ""
    @Persisted var topics: List<String>
    @Persisted var imagePaths: List<String>
    @Persisted var videoPaths: List<String>

    // 一个 Post 可以发布到多个平台；Job 通过 postID 关联，不重复保存任务列表。
    @Persisted var links: List<Link>
    @Persisted var createdAt: Date = .now
    @Persisted var updatedAt: Date = .now

    convenience init(skuID: UUID) {
        self.init()
        self.skuID = skuID
    }
}

final class Job: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: UUID = UUID()
    @Persisted(indexed: true) var skuID: UUID
    // 可以先指向 PostDraft.id；撤回草稿不代表远端任务取消。
    @Persisted(indexed: true) var postID: UUID?

    // image、video、copy
    @Persisted var kind: String = ""
    @Persisted(indexed: true) var status: String = "draft"

    // 只有供应商支持的异步任务 ID 才能轮询；请求 ID 不能当作任务 ID。
    @Persisted(indexed: true) var providerTaskID: String?
    @Persisted var providerRequestID: String?
    @Persisted var providerResultURL: String?
    @Persisted(indexed: true) var idempotencyKey: UUID = UUID()

    // 保存本次真正发送的 Prompt，便于重试和排查
    @Persisted var prompt: String = ""
    @Persisted var systemPromptVersion: Int = 1
    @Persisted var model: String?
    @Persisted var resultPaths: List<String>
    @Persisted var textResult: String?
    @Persisted var errorMessage: String?
    @Persisted var errorCode: String?
    @Persisted var submittedAt: Date?
    @Persisted var lastPolledAt: Date?

    @Persisted var createdAt: Date = .now
    @Persisted var updatedAt: Date = .now

    convenience init(skuID: UUID, kind: String, postID: UUID? = nil) {
        self.init()
        self.skuID = skuID
        self.kind = kind
        self.postID = postID
    }
}

final class Link: EmbeddedObject {
    // xiaohongshu、douyin、tiktok 等
    @Persisted var platform: String = ""
    @Persisted var url: String = ""
    @Persisted var externalID: String?
    @Persisted var publishedAt: Date?

    // 不覆盖旧记录；每次回传或采集都追加一条 Stat
    @Persisted var stats: List<Stat>
}

final class Stat: EmbeddedObject {
    // 累计值；nil 表示未获取，0 表示已获取且确实为零。
    @Persisted var observedAt: Date = .now
    @Persisted var views: Int64?
    @Persisted var likes: Int64?
    @Persisted var saves: Int64?
    @Persisted var comments: Int64?
    @Persisted var shares: Int64?
    @Persisted var inquiries: Int64?
    @Persisted var orders: Int64?
    // 金额使用分，避免 Double 精度问题
    @Persisted var revenueInCents: Int64?
    @Persisted var currency: String = "CNY"
    @Persisted var source: String = "manual"
    @Persisted var note: String = ""
}

// MARK: - Unsaved post draft

/// 值类型草稿；编辑或恢复一份副本不会改动已保存的 Post。
struct PostDraft: Identifiable, Sendable {
    let id: UUID
    let skuID: UUID
    var titles: [String] = []
    var selectedTitleIndex: Int = 0
    var body: String = ""
    var topics: [String] = []
    var imagePaths: [String] = []
    var videoPaths: [String] = []

    init(skuID: UUID) {
        id = UUID()
        self.skuID = skuID
    }

    @MainActor
    init(post: Post) {
        id = post.id
        skuID = post.skuID
        titles = Array(post.titles)
        selectedTitleIndex = post.selectedTitleIndex
        body = post.body
        topics = Array(post.topics)
        imagePaths = Array(post.imagePaths)
        videoPaths = Array(post.videoPaths)
    }
}
