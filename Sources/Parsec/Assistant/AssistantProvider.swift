import Foundation
import UniformTypeIdentifiers

enum AssistantEvent {
    case textDelta(String)
    case toolStarted(String)
    case finished(text: String, sessionID: String?, isError: Bool)
    case failed(String)
}

enum AssistantProviderKind: String, CaseIterable, Codable, Identifiable {
    case claudeCode
    case codexCLI
    case anthropicAPI
    case openAIAPI
    case localModels
    case customAPI

    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codexCLI: "Codex (ChatGPT)"
        case .anthropicAPI: "API de Anthropic"
        case .openAIAPI: "API de OpenAI"
        case .localModels: "Modelos locales"
        case .customAPI: BrowserStore.shared.settings.customProviderName
        }
    }

    @MainActor var pickerTitle: String {
        switch self {
        case .claudeCode, .codexCLI: assistantName
        default: displayName
        }
    }

    @MainActor var assistantName: String {
        switch self {
        case .claudeCode, .anthropicAPI: "Claude"
        case .codexCLI, .openAIAPI: "ChatGPT"
        case .localModels: "Local"
        case .customAPI: BrowserStore.shared.settings.customProviderName
        }
    }

    var detail: String {
        switch self {
        case .claudeCode: "Usa tu suscripción de Claude a través de Claude Code instalado en tu Mac."
        case .codexCLI: "Usa tu suscripción de ChatGPT a través de Codex CLI instalado en tu Mac."
        case .anthropicAPI: "Pago por uso con una API key de console.anthropic.com."
        case .openAIAPI: "Pago por uso con una API key de platform.openai.com."
        case .localModels: "Modelos que corren en tu Mac con Ollama. Privados, gratis y sin conexión."
        case .customAPI: "Cualquier servicio compatible con la API de OpenAI: Ollama, LM Studio, OpenRouter, Groq, Together y otros."
        }
    }

    @MainActor var logoURL: URL? {
        switch self {
        case .claudeCode, .anthropicAPI: URL(string: "https://claude.ai")
        case .codexCLI, .openAIAPI: URL(string: "https://chatgpt.com")
        case .localModels: LocalModels.websiteURL
        case .customAPI: URL(string: BrowserStore.shared.settings.customProviderBaseURL)
        }
    }

    var needsAPIKey: Bool {
        self == .anthropicAPI || self == .openAIAPI
    }

    var acceptsAPIKey: Bool {
        needsAPIKey || self == .customAPI
    }

    var supportsConnectors: Bool {
        self == .claudeCode
    }

    var supportsWebSearch: Bool {
        self == .claudeCode || self == .anthropicAPI
    }

    var defaultModel: String {
        switch self {
        case .claudeCode: "opus"
        case .codexCLI: ""
        case .anthropicAPI: "claude-opus-5"
        case .openAIAPI: "gpt-5"
        case .localModels, .customAPI: LocalModels.defaultModel
        }
    }
}

struct AssistantAttachment: Identifiable, Hashable {
    enum Kind {
        case image
        case pdf
        case text
        case other
    }

    let id = UUID()
    let fileURL: URL
    let name: String

    var kind: Kind {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) { return .text }
        return .other
    }

    var mediaType: String {
        UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    var symbolName: String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .other: "doc"
        }
    }
}

struct AssistantHistoryTurn {
    let isUser: Bool
    let text: String
}

struct AssistantRequest {
    let prompt: String
    let history: [AssistantHistoryTurn]
    let attachments: [AssistantAttachment]
    let systemPrompt: String
    let usesWebSearch: Bool
    let enabledConnectors: [String]
    let resumeSessionID: String?
    let model: String
    var usesIntegrations = true
}

@MainActor
protocol AssistantRun: AnyObject {
    func cancel()
}

@MainActor
enum AssistantProviderFactory {
    static func start(_ kind: AssistantProviderKind, request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) -> AssistantRun {
        if request.usesIntegrations && IntegrationStore.shared.hasEnabledServers {
            return IntegrationAssistantRun(provider: kind, request: request, onEvent: onEvent)
        }
        var prepared = request
        if request.usesIntegrations && !IntegrationStore.shared.skillContext.isEmpty {
            prepared = AssistantRequest(prompt: request.prompt, history: request.history, attachments: request.attachments, systemPrompt: request.systemPrompt + "\n" + IntegrationStore.shared.skillContext, usesWebSearch: request.usesWebSearch, enabledConnectors: request.enabledConnectors, resumeSessionID: request.resumeSessionID, model: request.model, usesIntegrations: false)
        }
        return startBase(kind, request: prepared, onEvent: onEvent)
    }

    static func startBase(_ kind: AssistantProviderKind, request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) -> AssistantRun {
        switch kind {
        case .claudeCode:
            let runner = ClaudeCodeRunner(onEvent: onEvent)
            runner.start(request)
            return runner
        case .codexCLI:
            let runner = CodexRunner(onEvent: onEvent)
            runner.start(request)
            return runner
        case .anthropicAPI:
            return HTTPAssistantRun(task: Task { await AnthropicAPIClient.stream(request, onEvent: onEvent) })
        case .openAIAPI:
            return HTTPAssistantRun(task: Task { await OpenAIAPIClient.stream(request, endpoint: OpenAIAPIClient.officialEndpoint, provider: .openAIAPI, onEvent: onEvent) })
        case .localModels:
            return HTTPAssistantRun(task: Task { await OpenAIAPIClient.stream(request, endpoint: LocalModels.chatEndpoint, provider: .localModels, onEvent: onEvent) })
        case .customAPI:
            let endpoint = OpenAIAPIClient.endpoint(forBaseURL: BrowserStore.shared.settings.customProviderBaseURL)
            return HTTPAssistantRun(task: Task { await OpenAIAPIClient.stream(request, endpoint: endpoint, provider: .customAPI, onEvent: onEvent) })
        }
    }
}

@MainActor
final class HTTPAssistantRun: AssistantRun {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

enum AssistantWorkspace {
    private static let folderName = "Assistant"
    private static let attachmentsFolderName = "attachments"

    static var folderURL: URL {
        let url = StorageConstants.applicationSupportURL.appending(path: folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var attachmentsURL: URL {
        let url = folderURL.appending(path: attachmentsFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func importAttachment(from sourceURL: URL) -> AssistantAttachment? {
        let destinationURL = attachmentsURL.appending(path: UUID().uuidString + "-" + sourceURL.lastPathComponent)
        guard (try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)) != nil else { return nil }
        return AssistantAttachment(fileURL: destinationURL, name: sourceURL.lastPathComponent)
    }

    static func saveAttachment(data: Data, name: String) -> AssistantAttachment? {
        let destinationURL = attachmentsURL.appending(path: UUID().uuidString + "-" + name)
        guard (try? data.write(to: destinationURL)) != nil else { return nil }
        return AssistantAttachment(fileURL: destinationURL, name: name)
    }
}

enum CommandLineTool {
    private static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

    static func locate(_ relativeCandidates: [String]) -> URL? {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return relativeCandidates
            .map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : homeURL.appending(path: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func environment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executableURL.deletingLastPathComponent().path + ":" + searchPath
        return environment
    }
}
