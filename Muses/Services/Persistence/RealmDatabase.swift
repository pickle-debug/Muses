import Foundation
import RealmSwift

enum RealmDatabase {
    // 数据库版本独立于 App 版本；结构或旧数据转换发生变化时才递增。
    static let schemaVersion: UInt64 = 1

    static func configuration(fileURL: URL? = nil) throws -> Realm.Configuration {
        var configuration = Realm.Configuration()
        if let fileURL {
            configuration.fileURL = fileURL
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let directory = support.appending(path: "Muses", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration.fileURL = directory.appending(path: "muses.realm")
        }
        configuration.schemaVersion = schemaVersion
        configuration.objectTypes = [Setting.self, SKU.self, Post.self, Job.self, Link.self, Stat.self]
        configuration.deleteRealmIfMigrationNeeded = false
        configuration.migrationBlock = { _, _ in
            // v1 是首个 Realm schema，没有旧 Realm 字段需要转换。
            // 后续升版本并添加独立 if oldVersion < N；JSON 导入不属于此回调。
        }
        return configuration
    }

    // ponytail: MVP 在主线程短事务内读写；数据量变大后改用专用 actor。
    @MainActor
    static func open(fileURL: URL? = nil) throws -> Realm {
        let realm = try Realm(configuration: configuration(fileURL: fileURL))
        if realm.object(ofType: Setting.self, forPrimaryKey: "default") == nil {
            try realm.write { realm.add(Setting()) }
        }
        return realm
    }
}
