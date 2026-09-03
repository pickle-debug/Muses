import Foundation
import Alamofire

final class OpenAIStyleProviderClient: MediaProvider, @unchecked Sendable {
    private let configuration: ProviderConfiguration
    private let credentialStore: any CredentialStore
    private let session: Session

    init(configuration: ProviderConfiguration, credentialStore: any CredentialStore, session: Session? = nil) throws {
        try ProviderConfigurationLoader.validate(configuration)
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.session = session ?? Session(configuration: URLSessionConfiguration.af.default)
    }

    func testConnection() async throws -> ConnectionResult {
        let request = try request(path: configuration.provider.connectionTestPath, method: "GET", timeoutMs: configuration.text.timeoutMs)
        let response = try await executeJSON(request)
        let availableModels = modelIdentifiers(in: response)
        let requiredModels = [configuration.models.text, configuration.models.image, configuration.models.video]
        let missingModels = requiredModels.filter { !availableModels.contains($0) }
        guard missingModels.isEmpty else {
            throw AppError.safe(
                "PROVIDER_MODELS_UNAVAILABLE",
                "当前 Key 无法使用配置的模型：\(missingModels.joined(separator: "、"))"
            )
        }
        return ConnectionResult(reachable: true, model: configuration.models.text)
    }

    func extractProductFacts(_ input: FactExtractionInput) async throws -> ProductFactDraft {
        guard (1...6).contains(input.referenceImageURLs.count) else {
            throw AppError.safe("PRODUCT_IMAGES_INVALID", "请选择商品参考图")
        }
        let images = try input.referenceImageURLs.map { url -> [String: Any] in
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= configuration.image.maximumDownloadBytes else {
                throw AppError.safe("ASSET_TOO_LARGE", "商品图片文件过大")
            }
            return ["type": "image_url", "image_url": ["url": "data:\(mimeType(for: url));base64,\(data.base64EncodedString())"]]
        }
        let instruction = """
        仅提取图片可见或用户明确提供的商品事实。无法确认的字段返回 null 或加入 uncertainFields。\
        只返回 JSON：category, material, specification, colors, visiblePatterns, visibleText, lockedFeatures, uncertainFields。
        用户商品名：\(input.productName)；用户真实卖点：\(input.sellingPoint)
        """
        var content: [[String: Any]] = [["type": "text", "text": instruction]]
        content.append(contentsOf: images)
        let payload: [String: Any] = [
            "model": configuration.models.text,
            "messages": [["role": "user", "content": content]],
            "response_format": ["type": "json_object"]
        ]
        let response = try await sendJSON(path: configuration.text.path, body: payload, idempotencyKey: input.idempotencyKey, timeoutMs: configuration.text.timeoutMs)
        let text = try responseText(from: response)
        return try decodeJSON(ProductFactDraft.self, text: text, code: "PRODUCT_FACT_PARSE_FAILED")
    }

    func generateImage(_ input: ImageGenerationInput) async throws -> ImageGenerationResult {
        guard (3...6).contains(input.referenceImageURLs.count) else {
            throw AppError.safe("PRODUCT_IMAGES_INVALID", "请提供 3–6 张商品参考图")
        }
        let fields = [
            "model": configuration.models.image,
            "prompt": input.prompt,
            "n": String(configuration.image.count),
            "aspect_ratio": configuration.image.aspectRatio,
            "output_format": input.outputFormat.rawValue
        ]
        let files = input.referenceImageURLs.enumerated().map {
            MultipartFile(fieldName: "image[]", fileName: "reference-\($0.offset + 1).\($0.element.pathExtension)", mimeType: mimeType(for: $0.element), url: $0.element)
        }
        let response = try await sendMultipart(path: configuration.image.path, fields: fields, files: files, idempotencyKey: input.idempotencyKey, timeoutMs: configuration.image.timeoutMs)
        let remoteURL = (JSONPath.value(at: configuration.image.responseUrlPath, in: response) as? String).flatMap(URL.init(string:))
        let base64 = JSONPath.value(at: configuration.image.responseBase64Path, in: response) as? String
        guard remoteURL != nil || base64 != nil else {
            throw AppError.safe("IMAGE_RESPONSE_INVALID", "图片生成结果不可用", retryable: true)
        }
        return ImageGenerationResult(
            remoteRequestID: configuration.image.requestIdPath.flatMap { JSONPath.value(at: $0, in: response) as? String },
            remoteURL: remoteURL,
            base64: base64,
            mimeType: input.outputFormat == .png ? "image/png" : "image/jpeg",
            revisedPrompt: configuration.image.revisedPromptPath.flatMap { JSONPath.value(at: $0, in: response) as? String }
        )
    }

    func createVideo(_ input: VideoGenerationInput) async throws -> RemoteVideoJob {
        let fields = [
            "model": configuration.models.video,
            "prompt": input.prompt,
            "duration": String(configuration.video.durationSeconds),
            "resolution": configuration.video.resolution,
            "audio": String(configuration.video.audio)
        ]
        let file = MultipartFile(fieldName: "image", fileName: input.imageURL.lastPathComponent, mimeType: mimeType(for: input.imageURL), url: input.imageURL)
        let response = try await sendMultipart(path: configuration.video.createPath, fields: fields, files: [file], idempotencyKey: input.idempotencyKey, timeoutMs: configuration.video.timeoutMs)
        guard let taskID = JSONPath.value(at: configuration.video.taskIdPath, in: response) as? String, !taskID.isEmpty else {
            throw AppError.safe("VIDEO_RESPONSE_INVALID", "AI 动态任务返回异常", retryable: true)
        }
        let rawStatus = JSONPath.value(at: configuration.video.statusPath, in: response) as? String
        return RemoteVideoJob(taskID: taskID, status: mapVideoStatus(rawStatus))
    }

    func getVideoJob(taskID: String) async throws -> RemoteVideoJobStatus {
        guard !taskID.isEmpty, !taskID.contains("/"), !taskID.contains("?") else {
            throw AppError.safe("VIDEO_TASK_ID_INVALID", "AI 动态任务标识无效")
        }
        let escaped = taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskID
        let path = configuration.video.statusPathTemplate.replacingOccurrences(of: "{taskId}", with: escaped)
        let request = try request(path: path, method: "GET", timeoutMs: configuration.video.timeoutMs)
        let response = try await executeJSON(request)
        let resultString = JSONPath.value(at: configuration.video.resultUrlPath, in: response) as? String
        return RemoteVideoJobStatus(
            taskID: taskID,
            status: mapVideoStatus(JSONPath.value(at: configuration.video.statusPath, in: response) as? String),
            progress: number(at: configuration.video.progressPath, in: response),
            resultURL: resultString.flatMap(URL.init(string:)),
            safeError: configuration.video.errorPath.flatMap { JSONPath.value(at: $0, in: response) as? String }.map(sanitizedProviderMessage)
        )
    }

    func generateCopy(_ input: CopyGenerationInput) async throws -> CopyPackageDraft {
        let factsData = try JSONEncoder().encode(input.facts)
        guard let factsJSON = String(data: factsData, encoding: .utf8) else {
            throw AppError.safe("COPY_INPUT_INVALID", "商品事实无法读取")
        }
        let instruction = """
        根据已确认事实生成小红书文案。只返回 JSON：titles(恰好3个), body, topics(8到12个), factClaims, warnings。\
        禁止虚构经历、价格、疗效、权威背书或用户评价；禁止项：\(input.prohibitedClaims.joined(separator: "、"))。\
        创意摘要：\(input.creativeSummary)；已确认事实：\(factsJSON)
        """
        let payload: [String: Any] = [
            "model": configuration.models.text,
            "messages": [["role": "user", "content": instruction]],
            "response_format": ["type": "json_object"]
        ]
        let response = try await sendJSON(path: configuration.text.path, body: payload, idempotencyKey: input.idempotencyKey, timeoutMs: configuration.text.timeoutMs)
        let draft = try decodeJSON(CopyPackageDraft.self, text: responseText(from: response), code: "COPY_PARSE_FAILED")
        guard draft.titles.count == 3, (8...12).contains(draft.topics.count) else {
            throw AppError.safe("COPY_PARSE_FAILED", "文案格式不完整", retryable: true)
        }
        return draft
    }

    private func sendJSON(path: String, body: [String: Any], idempotencyKey: UUID, timeoutMs: Int) async throws -> Any {
        var request = try request(path: path, method: "POST", timeoutMs: timeoutMs)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await executeJSON(request)
    }

    private func sendMultipart(path: String, fields: [String: String], files: [MultipartFile], idempotencyKey: UUID, timeoutMs: Int) async throws -> Any {
        var request = try request(path: path, method: "POST", timeoutMs: timeoutMs)
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let response = await session.upload(multipartFormData: { form in
            for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
                form.append(Data(value.utf8), withName: name)
            }
            for file in files {
                form.append(file.url, withName: file.fieldName, fileName: file.fileName, mimeType: file.mimeType)
            }
        }, with: request).serializingData().response
        let data = try responseData(from: response)
        return try validateJSON(data: data, response: response.response)
    }

    private func request(path: String, method: String, timeoutMs: Int) throws -> URLRequest {
        guard let key = credentialStore.apiKey(), !key.isEmpty else {
            throw AppError.safe("API_KEY_INVALID", "测试密钥无效或已过期")
        }
        let url = configuration.provider.baseUrl.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard url.scheme == "https", let host = url.host?.lowercased(), configuration.provider.allowedHosts.map({ $0.lowercased() }).contains(host) else {
            throw AppError.safe("CONFIG_INVALID", "当前生成配置不可用")
        }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutMs) / 1_000)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let response = await session.request(request).serializingData().response
        let data = try responseData(from: response)
        try validate(data: data, response: response.response)
        return data
    }

    private func executeJSON(_ request: URLRequest) async throws -> Any {
        let data = try await execute(request)
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw AppError.safe("PROVIDER_RESPONSE_INVALID", "生成服务返回格式异常", retryable: true) }
    }

    private func validateJSON(data: Data, response: HTTPURLResponse?) throws -> Any {
        try validate(data: data, response: response)
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw AppError.safe("PROVIDER_RESPONSE_INVALID", "生成服务返回格式异常", retryable: true) }
    }

    private func validate(data: Data, response: HTTPURLResponse?) throws {
        guard let http = response else {
            throw AppError.safe("NETWORK_RESPONSE_INVALID", "无法连接生成服务", retryable: true)
        }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw AppError.safe("API_KEY_INVALID", "测试密钥无效或已过期")
        case 402, 429: throw AppError.safe("API_QUOTA_EXHAUSTED", "当前测试额度已用完")
        case 500..<600: throw AppError.safe("PROVIDER_UNAVAILABLE", "生成服务暂时不可用", retryable: true, context: ["status": String(http.statusCode)])
        default: throw AppError.safe("PROVIDER_REQUEST_FAILED", "生成服务拒绝了请求", retryable: false, context: ["status": String(http.statusCode)])
        }
    }

    private func responseText(from object: Any) throws -> String {
        guard let text = JSONPath.value(at: configuration.text.responseTextPath, in: object) as? String else {
            throw AppError.safe("PROVIDER_RESPONSE_INVALID", "生成服务返回格式异常", retryable: true)
        }
        return text
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, text: String, code: String) throws -> T {
        let cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        do { return try JSONDecoder().decode(T.self, from: Data(cleaned.utf8)) }
        catch { throw AppError.safe(code, "AI 返回内容格式异常", retryable: true) }
    }

    private func mapVideoStatus(_ raw: String?) -> RemoteVideoStatus {
        guard let normalized = raw?.lowercased() else { return .unknown }
        for (status, values) in configuration.video.statusMap where values.map({ $0.lowercased() }).contains(normalized) {
            if let mapped = RemoteVideoStatus(rawValue: status) { return mapped }
        }
        return .unknown
    }

    private func modelIdentifiers(in response: Any) -> Set<String> {
        guard let models = JSONPath.value(at: "data", in: response) as? [[String: Any]] else { return [] }
        return Set(models.compactMap { $0["id"] as? String })
    }

    private func number(at path: String?, in object: Any) -> Double? {
        guard let path else { return nil }
        if let number = JSONPath.value(at: path, in: object) as? NSNumber { return number.doubleValue }
        if let string = JSONPath.value(at: path, in: object) as? String { return Double(string) }
        return nil
    }

    private func networkError(_ error: Error) -> AppError {
        let nsError = ((error as? AFError)?.underlyingError ?? error) as NSError
        let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
        return AppError.safe(isTimeout ? "REQUEST_TIMEOUT" : "NETWORK_FAILED", isTimeout ? "请求超时，提交结果可能未知" : "网络连接失败", retryable: true)
    }

    private func responseData(from response: AFDataResponse<Data>) throws -> Data {
        switch response.result {
        case .success(let data): return data
        case .failure(let error):
            if error.isExplicitlyCancelledError { throw CancellationError() }
            throw networkError(error)
        }
    }

    private func sanitizedProviderMessage(_ message: String) -> String {
        String(message.prefix(200)).replacingOccurrences(of: #"https?://\S+"#, with: "[URL]", options: .regularExpression)
    }
}

private struct MultipartFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let url: URL
}

private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "png": "image/png"
    case "heic", "heif": "image/heic"
    case "mov": "video/quicktime"
    case "mp4", "m4v": "video/mp4"
    default: "image/jpeg"
    }
}
