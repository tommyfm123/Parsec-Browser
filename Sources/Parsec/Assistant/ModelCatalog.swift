import Foundation

struct ModelOption: Identifiable, Hashable {
    let provider: AssistantProviderKind
    let model: String
    let title: String
    var detail = ""
    var id: String { provider.rawValue + model }
}

@MainActor
enum ModelCatalog {
    private static var settings: BrowserSettings { BrowserStore.shared.settings }

    static func isAvailable(_ provider: AssistantProviderKind) -> Bool {
        switch provider {
        case .claudeCode: ClaudeCodeRunner.executableURL != nil
        case .codexCLI: CodexRunner.executableURL != nil
        case .anthropicAPI, .openAIAPI: APIKeyStore.hasKey(for: provider)
        case .localModels: LocalModels.shared.isServerRunning && !LocalModels.shared.installed.isEmpty
        case .customAPI: settings.customProviderBaseURL != BrowserSettings().customProviderBaseURL || APIKeyStore.hasKey(for: provider)
        }
    }

    private static let codexModelsCacheComponents = [".codex", "models_cache.json"]
    private static let codexDefaultEntry: (model: String, title: String, detail: String) = ("", "Predeterminado", "El modelo configurado en Codex")

    private struct CodexModelsCache: Decodable {
        struct Entry: Decodable {
            let slug: String
            let displayName: String
            let description: String?
            let visibility: String?
        }
        let models: [Entry]
    }

    private static var codexEntries: [(model: String, title: String, detail: String)] {
        let cacheURL = codexModelsCacheComponents.reduce(FileManager.default.homeDirectoryForCurrentUser) { $0.appending(path: $1) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? decoder.decode(CodexModelsCache.self, from: $0) }
        let listed = (cached?.models ?? []).filter { $0.visibility == "list" }.map { ($0.slug, $0.displayName, $0.description ?? "") }
        return [codexDefaultEntry] + listed
    }

    static func options(for provider: AssistantProviderKind) -> [ModelOption] {
        let entries: [(model: String, title: String, detail: String)] = switch provider {
        case .claudeCode: [("opus", "Claude Opus", "El más capaz, ideal para investigar"), ("sonnet", "Claude Sonnet", "Rápido y muy capaz"), ("haiku", "Claude Haiku", "El más veloz")]
        case .anthropicAPI: [("claude-opus-5", "Claude Opus 5", "El más capaz"), ("claude-sonnet-5", "Claude Sonnet 5", "Equilibrado"), ("claude-haiku-4-5", "Claude Haiku 4.5", "El más veloz")]
        case .codexCLI: codexEntries
        case .openAIAPI: [("gpt-5", "GPT-5", "El más capaz"), ("gpt-5-mini", "GPT-5 mini", "Rápido y económico")]
        case .localModels: LocalModels.shared.installed.map { ($0, $0, "En tu Mac, sin conexión") }
        case .customAPI: [(settings.assistantModel(for: .customAPI), settings.customProviderName, settings.customProviderBaseURL)]
        }
        return entries.map { ModelOption(provider: provider, model: $0.model, title: $0.title, detail: $0.detail) }
    }

    static var availableProviders: [AssistantProviderKind] {
        AssistantProviderKind.allCases.filter(isAvailable)
    }

    static var current: ModelOption {
        let provider = settings.assistantProvider
        let model = settings.assistantModel(for: provider)
        return options(for: provider).first { $0.model == model }
            ?? ModelOption(provider: provider, model: model, title: model.isEmpty ? provider.assistantName : model)
    }

    static func select(_ option: ModelOption) {
        let store = BrowserStore.shared
        store.settings.assistantProvider = option.provider
        store.settings.assistantModels[option.provider.rawValue] = option.model
        store.saveSoon()
    }
}
