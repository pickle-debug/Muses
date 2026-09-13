import Foundation
import RealmSwift

// 在 Xcode 的测试入口调用 try RealmChecks.run()；只写独立临时目录。
@MainActor
enum RealmChecks {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MusesRealmChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "test.realm")
        let skuID = UUID(), postID = UUID(), jobID = UUID()

        try autoreleasepool {
            let realm = try RealmDatabase.open(fileURL: fileURL)
            let sku = SKU(code: "CHECK-001", name: "杯子", sellingPoint: "500ml")
            sku.id = skuID
            let post = Post(skuID: sku.id)
            post.id = postID
            post.body = "已保存文案"
            let image = Job(skuID: sku.id, kind: "image", postID: post.id)
            image.id = jobID
            image.providerTaskID = "test-remote-image-id"
            let video = Job(skuID: sku.id, kind: "video", postID: post.id)
            video.providerTaskID = "test-remote-video-id"
            assert(image.id != video.id && image.idempotencyKey != video.idempotencyKey)

            let link = Link()
            link.platform = "xiaohongshu"
            let first = Stat()
            first.observedAt = Date(timeIntervalSince1970: 1_000)
            first.views = 100
            first.likes = 0
            let second = Stat()
            second.observedAt = Date(timeIntervalSince1970: 4_600)
            second.views = 360
            link.stats.append(objectsIn: [first, second])
            post.links.append(link)
            let other = Link()
            other.platform = "tiktok"
            post.links.append(other)
            try realm.write {
                realm.add(sku)
                realm.add(post)
                realm.add(image)
                realm.add(video)
            }

            var draft = PostDraft(post: post)
            let previous = draft
            draft.body = "未保存文案"
            draft.titles.append("新标题")
            assert(post.body == "已保存文案" && post.titles.isEmpty)
            draft = previous
            assert(draft.body == post.body && draft.titles.isEmpty)
        }

        try autoreleasepool {
            let realm = try RealmDatabase.open(fileURL: fileURL)
            assert(realm.objects(Setting.self).count == 1)
            assert(realm.object(ofType: Setting.self, forPrimaryKey: "default")?.legacyImportedAt == nil)
            assert(realm.object(ofType: SKU.self, forPrimaryKey: skuID)?.code == "CHECK-001")
            assert(realm.objects(Job.self).filter("postID == %@", postID as NSUUID).count == 2)
            assert(realm.object(ofType: Job.self, forPrimaryKey: jobID)?.providerTaskID == "test-remote-image-id")
            guard let post = realm.object(ofType: Post.self, forPrimaryKey: postID) else {
                assertionFailure("Post 丢失")
                return
            }
            assert(post.links.count == 2)
            let samples = post.links[0].stats
            assert(samples.count == 2 && samples[0].views == 100 && samples[1].views == 360)
            assert(samples[0].likes == 0 && samples[0].shares == nil)
            assert(samples[1].observedAt > samples[0].observedAt)
            let configuration = try RealmDatabase.configuration(fileURL: fileURL)
            assert(!configuration.deleteRealmIfMigrationNeeded)
            assert(configuration.schemaVersion == RealmDatabase.schemaVersion)
        }
    }
}
