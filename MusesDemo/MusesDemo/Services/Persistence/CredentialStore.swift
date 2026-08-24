import Foundation

protocol CredentialStore: Sendable {
    func apiKey() -> String?
    func setApiKey(_ value: String)
    func deleteApiKey()
}

final class UserDefaultsCredentialStore: CredentialStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, storageKey: String = "muses.demo.temporary-api-key") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func apiKey() -> String? {
        lock.withLock {
            guard let value = defaults.string(forKey: storageKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
    }

    func setApiKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            if trimmed.isEmpty { defaults.removeObject(forKey: storageKey) }
            else { defaults.set(trimmed, forKey: storageKey) }
        }
    }

    func deleteApiKey() {
        lock.withLock { defaults.removeObject(forKey: storageKey) }
    }
}
