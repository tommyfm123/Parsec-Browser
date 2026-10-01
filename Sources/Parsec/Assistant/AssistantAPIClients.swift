import Foundation
import Security

enum APIKeyStore {
    private static let service = "dev.tommy.parsec.api-keys"

    static func key(for provider: AssistantProviderKind) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasKey(for provider: AssistantProviderKind) -> Bool {
        var query = baseQuery(provider)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func save(_ key: String, for provider: AssistantProviderKind) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        var query = baseQuery(provider)
        query[kSecValueData as String] = Data(trimmedKey.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(_ provider: AssistantProviderKind) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
    }
}

enum ServerSentEvents {
    private static let dataPrefix = "data: "
    private static let maximumErrorCharacters = 4096
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: MCPRedirectPolicy(), delegateQueue: nil)
    }()
    static let doneMarker = "[DONE]"

    static func lines(for request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        guard let url = request.url, WebSecurityPolicy.isSecureEndpoint(url) else { throw APIError.invalidEndpoint }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumErrorCharacters else { break }
                data.append(byte)
            }
            throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(decoding: data, as: UTF8.self))
        }
        return bytes.lines
    }

    static func payload(fromLine line: String) -> String? {
        line.hasPrefix(dataPrefix) ? String(line.dropFirst(dataPrefix.count)) : nil
    }

    static func json(_ payload: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
    }
}

enum APIError: LocalizedError {
    case missingKey(providerName: String)
    case invalidEndpoint
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let providerName): "Falta la API key de \(providerName). Agrégala en Configuración → IA."
        case .invalidEndpoint: "La URL del proveedor personalizado no es válida."
        case .http(let status, let body): "Error \(status): \(APIError.message(from: body))"
        }
    }

    private static func message(from body: String) -> String {
        let payload = ServerSentEvents.json(body)
        let errorObject = payload?["error"] as? [String: Any]
        return errorObject?["message"] as? String ?? body
    }
}

enum AttachmentEncoder {
    static func textContents(of attachment: AssistantAttachment) -> String {
        let contents = (try? String(contentsOf: attachment.fileURL, encoding: .utf8)) ?? ""
        return "<archivo nombre=\"\(attachment.name)\">\n\(contents)\n</archivo>"
    }

    static func base64(of attachment: AssistantAttachment) -> String {
        (try? Data(contentsOf: attachment.fileURL))?.base64EncodedString() ?? ""
    }
}

@MainActor
enum AnthropicAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    private static let maxTokens = 64000
    private static let webSearchTool: [String: Any] = ["type": "web_search_20260209", "name": "web_search"]

    static func stream(_ request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async {
        do {
            guard let apiKey = APIKeyStore.key(for: .anthropicAPI) else { throw APIError.missingKey(providerName: AssistantProviderKind.anthropicAPI.displayName) }
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            urlRequest.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
            urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))
            var fullText = ""
            for try await line in try await ServerSentEvents.lines(for: urlRequest) {
                try Task.checkCancellation()
                guard let payload = ServerSentEvents.payload(fromLine: line), let event = ServerSentEvents.json(payload) else { continue }
                let delta = event["delta"] as? [String: Any]
                let contentBlock = event["content_block"] as? [String: Any]
                if contentBlock?["type"] as? String == "server_tool_use", let toolName = contentBlock?["name"] as? String {
                    onEvent(.toolStarted(toolName))
                }
                if event["type"] as? String == "content_block_delta", delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String {
                    fullText += text
                    onEvent(.textDelta(text))
                }
                if delta?["stop_reason"] as? String == "refusal" {
                    return onEvent(.finished(text: fullText.isEmpty ? "El modelo no puede responder esa consulta." : fullText, sessionID: nil, isError: fullText.isEmpty))
                }
            }
            onEvent(.finished(text: fullText, sessionID: nil, isError: false))
        } catch is CancellationError {
            onEvent(.failed("Respuesta detenida."))
        } catch {
            onEvent(.failed(error.localizedDescription))
        }
    }

    private static func body(for request: AssistantRequest) -> [String: Any] {
        let historyMessages: [[String: Any]] = request.history.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        var body: [String: Any] = [
            "model": request.model.isEmpty ? AssistantProviderKind.anthropicAPI.defaultModel : request.model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": request.systemPrompt,
            "thinking": ["type": "adaptive"],
            "fallbacks": "default",
            "messages": historyMessages + [["role": "user", "content": content(for: request)]],
        ]
        if request.usesWebSearch { body["tools"] = [webSearchTool] }
        return body
    }

    private static func content(for request: AssistantRequest) -> [[String: Any]] {
        let attachmentBlocks: [[String: Any]] = request.attachments.map { attachment in
            switch attachment.kind {
            case .image:
                ["type": "image", "source": ["type": "base64", "media_type": attachment.mediaType, "data": AttachmentEncoder.base64(of: attachment)]]
            case .pdf:
                ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": AttachmentEncoder.base64(of: attachment)]]
            case .text, .other:
                ["type": "text", "text": AttachmentEncoder.textContents(of: attachment)]
            }
        }
        return attachmentBlocks + [["type": "text", "text": request.prompt]]
    }
}

@MainActor
enum OpenAIAPIClient {
    static let officialEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let completionsPath = "chat/completions"

    static func endpoint(forBaseURL baseURL: String) -> URL? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)), WebSecurityPolicy.isSecureEndpoint(url) else { return nil }
        return url.appending(path: completionsPath)
    }

    static func stream(_ request: AssistantRequest, endpoint: URL?, provider: AssistantProviderKind, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async {
        do {
            let apiKey = APIKeyStore.key(for: provider)
            guard let endpoint else { throw APIError.invalidEndpoint }
            guard apiKey != nil || !provider.needsAPIKey else { throw APIError.missingKey(providerName: provider.displayName) }
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            if let apiKey { urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))
            var fullText = ""
            for try await line in try await ServerSentEvents.lines(for: urlRequest) {
                try Task.checkCancellation()
                guard let payload = ServerSentEvents.payload(fromLine: line), payload != ServerSentEvents.doneMarker, let event = ServerSentEvents.json(payload) else { continue }
                let choices = event["choices"] as? [[String: Any]]
                let delta = choices?.first?["delta"] as? [String: Any]
                guard let text = delta?["content"] as? String else { continue }
                fullText += text
                onEvent(.textDelta(text))
            }
            onEvent(.finished(text: fullText, sessionID: nil, isError: false))
        } catch is CancellationError {
            onEvent(.failed("Respuesta detenida."))
        } catch {
            onEvent(.failed(error.localizedDescription))
        }
    }

    private static func body(for request: AssistantRequest) -> [String: Any] {
        let historyMessages: [[String: Any]] = request.history.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        return [
            "model": request.model,
            "stream": true,
            "messages": [["role": "system", "content": request.systemPrompt]] + historyMessages + [["role": "user", "content": content(for: request)]],
        ]
    }

    private static func content(for request: AssistantRequest) -> [[String: Any]] {
        let attachmentParts: [[String: Any]] = request.attachments.map { attachment in
            switch attachment.kind {
            case .image:
                ["type": "image_url", "image_url": ["url": "data:\(attachment.mediaType);base64,\(AttachmentEncoder.base64(of: attachment))"]]
            case .pdf:
                ["type": "file", "file": ["filename": attachment.name, "file_data": "data:application/pdf;base64,\(AttachmentEncoder.base64(of: attachment))"]]
            case .text, .other:
                ["type": "text", "text": AttachmentEncoder.textContents(of: attachment)]
            }
        }
        return attachmentParts + [["type": "text", "text": request.prompt]]
    }
}
