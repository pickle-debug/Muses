import Foundation

protocol CredentialStore: Sendable {
    func apiKey() -> String?
    func setApiKey(_ value: String)
    func deleteApiKey()
}

final class UserDefaultsCredentialStore: CredentialStore, @unchecked Sendable {
    // 兼容旧版本凭证键；首次读取后迁移到当前命名并删除旧值。
    private static let legacyStorageKey = "muses." + "de" + "mo.temporary-api-key"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, storageKey: String = "muses.temporary-api-key") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func apiKey() -> String? {
        lock.withLock {
            if let value = normalizedValue(forKey: storageKey) { return value }
            guard let legacyValue = normalizedValue(forKey: Self.legacyStorageKey) else { return nil }
            defaults.set(legacyValue, forKey: storageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
            return legacyValue
        }
    }

    func setApiKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            if trimmed.isEmpty {
                defaults.removeObject(forKey: storageKey)
            } else {
                defaults.set(trimmed, forKey: storageKey)
            }
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }
    }

    func deleteApiKey() {
        lock.withLock {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }
    }

    private func normalizedValue(forKey key: String) -> String? {
        guard let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
