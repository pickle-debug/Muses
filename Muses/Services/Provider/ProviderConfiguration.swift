import Foundation

struct ProviderConfiguration: Codable, Sendable {
    struct Provider: Codable, Sendable {
        struct Authentication: Codable, Sendable { let type: String }
        let id: String
        let baseUrl: URL
        let allowedHosts: [String]
        let auth: Authentication
        let connectionTestPath: String
    }

    struct Models: Codable, Sendable {
        let text: String
        let image: String
        let video: String
    }

    struct TextEndpoint: Codable, Sendable {
        let path: String
        let responseTextPath: String
        let timeoutMs: Int
    }

    struct ImageEndpoint: Codable, Sendable {
        let path: String
        let requestEncoding: String
        let responseMode: String
        let responseUrlPath: String
        let responseBase64Path: String
        let requestIdPath: String?
        let revisedPromptPath: String?
        let count: Int
        let aspectRatio: String
        let timeoutMs: Int
        let maximumDownloadBytes: Int64
    }

    struct VideoEndpoint: Codable, Sendable {
        let createPath: String
        let statusPathTemplate: String
        let taskIdPath: String
        let statusPath: String
        let progressPath: String?
        let resultUrlPath: String
        let errorPath: String?
        let statusMap: [String: [String]]
        let durationSeconds: Int
        let resolution: String
        let audio: Bool
        let pollIntervalMs: Int
        let maxPollDurationMs: Int
        let timeoutMs: Int
        let maximumDownloadBytes: Int64
    }

    let schemaVersion: Int
    let provider: Provider
    let models: Models
    let text: TextEndpoint
    let image: ImageEndpoint
    let video: VideoEndpoint
}

enum ProviderConfigurationLoader {
    static func load(bundle: Bundle = .main, resource: String = "provider.config", allowPlaceholders: Bool = false) throws -> ProviderConfiguration {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用", context: ["reason": "resource_missing"])
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try rejectSecretKeys(in: data)
            let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
            try validate(configuration, allowPlaceholders: allowPlaceholders)
            return configuration
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用", context: ["reason": "decode_failed"])
        }
    }

    static func validate(_ value: ProviderConfiguration, allowPlaceholders: Bool = false) throws {
        guard value.schemaVersion == 1,
              value.provider.baseUrl.scheme?.lowercased() == "https",
              let host = value.provider.baseUrl.host?.lowercased(),
              value.provider.allowedHosts.map({ $0.lowercased() }).contains(host),
              value.provider.auth.type == "bearer",
              allowPlaceholders || !host.hasSuffix(".invalid"),
              allowPlaceholders || validModelName(value.models.text),
              allowPlaceholders || validModelName(value.models.image),
              allowPlaceholders || validModelName(value.models.video),
              value.image.requestEncoding == "multipart",
              ["url_or_b64_json", "url", "b64_json"].contains(value.image.responseMode),
              value.image.count == 1,
              value.image.aspectRatio == "3:4",
              (3...5).contains(value.video.durationSeconds),
              value.video.resolution == "720p",
              value.video.audio == false,
              value.video.pollIntervalMs >= 1_000,
              value.video.maxPollDurationMs >= value.video.pollIntervalMs,
              value.image.maximumDownloadBytes > 0,
              value.video.maximumDownloadBytes > 0 else {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用", context: ["reason": "constraint_failed"])
        }

        let paths = [value.provider.connectionTestPath, value.text.path, value.image.path, value.video.createPath]
        guard paths.allSatisfy({ $0.hasPrefix("/") && URL(string: $0)?.host == nil }),
              value.video.statusPathTemplate.hasPrefix("/"),
              URL(string: value.video.statusPathTemplate.replacingOccurrences(of: "{taskId}", with: "task"))?.host == nil else {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用", context: ["reason": "unsafe_path"])
        }
    }

    private static func validModelName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && !normalized.uppercased().contains("REPLACE_ME")
    }

    private static func rejectSecretKeys(in data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        let forbidden = Set(["apikey", "api_key", "secret", "token", "authorization"])
        func containsForbiddenKey(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                return dictionary.contains { forbidden.contains($0.key.lowercased()) || containsForbiddenKey($0.value) }
            }
            if let array = value as? [Any] { return array.contains(where: containsForbiddenKey) }
            return false
        }
        guard !containsForbiddenKey(object) else {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用", context: ["reason": "embedded_secret"])
        }
    }
}

enum JSONPath {
    static func value(at path: String, in object: Any) -> Any? {
        var current: Any? = object
        for component in tokenize(path) {
            switch component {
            case .key(let key): current = (current as? [String: Any])?[key]
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }

    private enum Component { case key(String), index(Int) }

    private static func tokenize(_ path: String) -> [Component] {
        var result: [Component] = []
        var key = ""
        var indexText = ""
        var insideIndex = false
        for character in path {
            switch character {
            case "." where !insideIndex:
                if !key.isEmpty { result.append(.key(key)); key = "" }
            case "[":
                if !key.isEmpty { result.append(.key(key)); key = "" }
                insideIndex = true
            case "]" where insideIndex:
                if let index = Int(indexText) { result.append(.index(index)) }
                indexText = ""
                insideIndex = false
            default:
                if insideIndex { indexText.append(character) } else { key.append(character) }
            }
        }
        if !key.isEmpty { result.append(.key(key)) }
        return result
    }
}
