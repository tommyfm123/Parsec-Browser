import AppKit
import Observation

enum CommandAction: String, CaseIterable {
    case newSpace = "Nuevo Space"
    case splitView = "Dividir vista"
    case copyURL = "Copiar URL"
    case togglePin = "Fijar o desfijar pestaña"
    case privateWindow = "Nueva ventana privada"
    case editTheme = "Editar tema del Space"
    case toggleSidebar = "Mostrar u ocultar sidebar"
    case toggleLayout = "Cambiar a pestañas arriba o sidebar"
    case settings = "Configuración"
    case downloads = "Abrir carpeta de descargas"
    case assistant = "Preguntar a Claude"
    case history = "Historial de conversaciones"

    var symbolName: String {
        switch self {
        case .newSpace: "plus.square.on.square"
        case .splitView: "rectangle.split.2x1"
        case .copyURL: "link"
        case .togglePin: "pin"
        case .privateWindow: "eyeglasses"
        case .editTheme: "paintpalette"
        case .toggleSidebar: "sidebar.left"
        case .toggleLayout: "rectangle.topthird.inset.filled"
        case .settings: "gearshape"
        case .downloads: "arrow.down.circle"
        case .assistant: "sparkle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum QuickAction: String, CaseIterable, Codable {
    case assistant
    case newDocument
    case history
    case splitView
    case newSpace
    case privateWindow
    case settings
    case downloads
    case editTheme
    case toggleLayout
    case copyURL
    case togglePin

    static let defaults: [QuickAction] = [.assistant, .newDocument, .history, .splitView, .newSpace, .privateWindow, .settings]

    var commandAction: CommandAction? {
        switch self {
        case .assistant: .assistant
        case .newDocument: nil
        case .history: .history
        case .splitView: .splitView
        case .newSpace: .newSpace
        case .privateWindow: .privateWindow
        case .settings: .settings
        case .downloads: .downloads
        case .editTheme: .editTheme
        case .toggleLayout: .toggleLayout
        case .copyURL: .copyURL
        case .togglePin: .togglePin
        }
    }

    @MainActor var title: String {
        switch self {
        case .assistant: "Preguntar a \(BrowserStore.shared.settings.assistantProvider.assistantName)"
        case .newDocument: "Nuevo documento"
        default: commandAction?.rawValue ?? ""
        }
    }

    var symbolName: String {
        commandAction?.symbolName ?? "doc.badge.plus"
    }

    var isAvailableInPrivate: Bool {
        ![.assistant, .newDocument, .history, .newSpace].contains(self)
    }
}

struct CommandResult: Identifiable, Equatable {
    enum Kind: Equatable {
        case openTab(nodeID: UUID)
        case url(URL)
        case suggestion(String)
        case action(CommandAction)
        case askAssistant(String)
        case newDocument(DocsProvider)
        case conversation(UUID)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let symbolName: String
    let iconURL: URL?
    var section: String?
}

@MainActor
@Observable
final class CommandBarModel {
    private static let openTabLimit = 4
    private static let actionLimit = 3
    private static let suggestionLimit = 4
    private static let recentTabLimit = 4
    private static let recentTabsSection = "Pestañas recientes"
    private static let quickActionsSection = "Acciones rápidas"
    private static let favoritesSection = "Favoritos"
    private static let conversationsSection = "Conversaciones recientes"
    private static let conversationLimit = 3
    private static let conversationSubtitle = "Conversación"

    let mode: CommandBarMode
    var query: String {
        didSet { refreshResults() }
    }
    private(set) var results: [CommandResult] = []
    var selectedIndex = 0
    @ObservationIgnored private weak var windowModel: WindowModel?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    init(windowModel: WindowModel, mode: CommandBarMode, initialText: String) {
        self.windowModel = windowModel
        self.mode = mode
        self.query = initialText
        refreshResults()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    func activateSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        activate(results[selectedIndex])
    }

    func activate(_ result: CommandResult) {
        guard let windowModel else { return }
        windowModel.dismissCommandBar()
        switch result.kind {
        case .openTab(let nodeID):
            guard let node = windowModel.store.node(nodeID) ?? windowModel.currentSpace.today.find(nodeID) else { return }
            windowModel.reveal(node)
        case .url(let url):
            windowModel.open(url, mode: mode)
        case .suggestion(let text):
            guard let url = InputResolver.searchURL(for: text) else { return }
            windowModel.open(url, mode: mode)
        case .action(let action):
            CommandRouter.perform(action, in: windowModel)
        case .newDocument(let provider):
            _ = windowModel.openInNewTab(provider.newDocumentURL)
        case .conversation(let conversationID):
            windowModel.openConversation(conversationID)
        case .askAssistant(let question):
            windowModel.isAssistantPresented = true
            windowModel.assistant.send(question)
        }
    }

    private func refreshResults() {
        suggestionTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        selectedIndex = 0
        guard let windowModel else { return results = [] }
        guard !trimmedQuery.isEmpty else { return results = mode == .newTab ? defaultResults(in: windowModel) : [] }
        let destination = InputResolver.destination(for: trimmedQuery)
        let destinationResults = destination.map { [destinationResult(for: $0, query: trimmedQuery)] } ?? []
        let assistantResults = windowModel.isPrivate ? [] : [assistantResult(for: trimmedQuery)]
        let tabResults = openTabResults(matching: trimmedQuery, in: windowModel)
        let tabURLs = Set(tabResults.compactMap(\.iconURL))
        let historyResults = windowModel.isPrivate ? [] : historyResults(matching: trimmedQuery, in: windowModel, excluding: tabURLs)
        let documentResults = Self.docsKeywords.contains(trimmedQuery.lowercased()) ? [documentResult()] : []
        let leadingResults = documentResults + destinationResults + assistantResults
        let conversations = windowModel.isPrivate ? [] : conversationResults(matching: trimmedQuery, in: windowModel)
        results = leadingResults + tabResults + conversations + historyResults + actionResults(matching: trimmedQuery)
        scheduleSuggestions(for: trimmedQuery, isEnabled: windowModel.store.settings.showsSearchSuggestions && !windowModel.isPrivate)
    }

    func askAssistantWithQuery() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty, windowModel?.isPrivate == false else { return }
        activate(assistantResult(for: trimmedQuery))
    }

    private func defaultResults(in windowModel: WindowModel) -> [CommandResult] {
        let settings = BrowserStore.shared.settings
        let favorites = settings.commandBarShowsFavorites ? favoriteResults(in: windowModel) : []
        let recentTabs = settings.commandBarShowsRecentTabs ? recentTabResults(in: windowModel) : []
        let conversations = settings.commandBarShowsConversations && !windowModel.isPrivate ? recentConversationResults(in: windowModel) : []
        let actions = settings.commandBarActions
            .filter { !windowModel.isPrivate || $0.isAvailableInPrivate }
            .map(quickActionResult)
        return favorites + recentTabs + conversations + actions
    }

    private func favoriteResults(in windowModel: WindowModel) -> [CommandResult] {
        windowModel.favorites.allTabs.prefix(Self.recentTabLimit).map { node in
            CommandResult(kind: .openTab(nodeID: node.id), title: node.displayTitle, subtitle: node.displayHost, symbolName: "star", iconURL: node.liveURL, section: Self.favoritesSection)
        }
    }

    private func recentTabResults(in windowModel: WindowModel) -> [CommandResult] {
        windowModel.currentSpace.allNodes.allTabs
            .filter { $0.page != nil && $0.liveURL != nil && $0.id != windowModel.activeTab?.id }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .prefix(Self.recentTabLimit)
            .map { node in
                CommandResult(kind: .openTab(nodeID: node.id), title: node.displayTitle, subtitle: node.displayHost, symbolName: "arrow.right.square", iconURL: node.liveURL, section: Self.recentTabsSection)
            }
    }

    private func recentConversationResults(in windowModel: WindowModel) -> [CommandResult] {
        ConversationStore.shared.list(profileID: windowModel.profileID).prefix(Self.conversationLimit).map { conversation in
            CommandResult(kind: .conversation(conversation.id), title: conversation.title, subtitle: "", symbolName: "bubble.left.and.text.bubble.right", iconURL: nil, section: Self.conversationsSection)
        }
    }

    private func quickActionResult(_ action: QuickAction) -> CommandResult {
        guard let commandAction = action.commandAction else {
            var document = documentResult()
            document.section = Self.quickActionsSection
            return document
        }
        return CommandResult(kind: .action(commandAction), title: action.title, subtitle: "", symbolName: action.symbolName, iconURL: nil, section: Self.quickActionsSection)
    }

    private static let docsKeywords: Set<String> = ["docs", "doc", "documento", "nuevo documento"]

    private func documentResult() -> CommandResult {
        let provider = BrowserStore.shared.settings.docsProvider
        return CommandResult(kind: .newDocument(provider), title: "Nuevo documento", subtitle: provider.displayName, symbolName: "doc.badge.plus", iconURL: provider.logoURL)
    }

    private func assistantResult(for query: String) -> CommandResult {
        let provider = BrowserStore.shared.settings.assistantProvider
        return CommandResult(kind: .askAssistant(query), title: query, subtitle: "Preguntar a \(provider.assistantName)", symbolName: "sparkle", iconURL: provider.logoURL)
    }

    private func destinationResult(for url: URL, query: String) -> CommandResult {
        let isSearch = url.absoluteString.hasPrefix(WebConstants.googleSearchURL)
        return CommandResult(
            kind: .url(url),
            title: isSearch ? query : url.absoluteString,
            subtitle: isSearch ? "Buscar en Google" : "Abrir",
            symbolName: isSearch ? "magnifyingglass" : "globe",
            iconURL: nil
        )
    }

    private func openTabResults(matching query: String, in windowModel: WindowModel) -> [CommandResult] {
        let candidateNodes = windowModel.isPrivate ? windowModel.currentSpace.today.allTabs : windowModel.store.allTabNodes
        return candidateNodes
            .filter { node in matches(node.displayTitle, query) || matches(node.liveURL?.absoluteString ?? "", query) }
            .prefix(Self.openTabLimit)
            .map { node in
                CommandResult(kind: .openTab(nodeID: node.id), title: node.displayTitle, subtitle: "Ir a la pestaña", symbolName: "arrow.right.square", iconURL: node.liveURL)
            }
    }

    private func historyResults(matching query: String, in windowModel: WindowModel, excluding excludedURLs: Set<URL>) -> [CommandResult] {
        var seenTitles: Set<String> = []
        return windowModel.store.history.search(query, profileID: windowModel.profileID)
            .filter { !excludedURLs.contains($0.url) && seenTitles.insert($0.title.isEmpty ? $0.url.absoluteString : $0.title).inserted }
            .map { entry in
                CommandResult(kind: .url(entry.url), title: entry.title.isEmpty ? entry.url.absoluteString : entry.title, subtitle: entry.url.host() ?? "", symbolName: "clock", iconURL: entry.url)
            }
    }

    private func conversationResults(matching query: String, in windowModel: WindowModel) -> [CommandResult] {
        ConversationStore.shared.list(profileID: windowModel.profileID, matching: query)
            .prefix(Self.conversationLimit)
            .map { CommandResult(kind: .conversation($0.id), title: $0.title, subtitle: Self.conversationSubtitle, symbolName: "bubble.left.and.text.bubble.right", iconURL: nil) }
    }

    private func actionResults(matching query: String) -> [CommandResult] {
        CommandAction.allCases
            .filter { matches($0.rawValue, query) }
            .prefix(Self.actionLimit)
            .map { CommandResult(kind: .action($0), title: $0.rawValue, subtitle: "Acción", symbolName: $0.symbolName, iconURL: nil) }
    }

    private func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func scheduleSuggestions(for query: String, isEnabled: Bool) {
        guard isEnabled, !query.contains("://") else { return }
        suggestionTask = Task {
            try? await Task.sleep(for: LifecycleConstants.suggestionDebounce)
            guard !Task.isCancelled else { return }
            let suggestions = await SearchSuggestions.fetch(for: query)
            guard !Task.isCancelled else { return }
            let existingTitles = Set(results.map(\.title))
            let suggestionResults = suggestions
                .filter { $0 != query && !existingTitles.contains($0) }
                .prefix(Self.suggestionLimit)
                .map { CommandResult(kind: .suggestion($0), title: $0, subtitle: "Sugerencia", symbolName: "magnifyingglass", iconURL: nil) }
            results.append(contentsOf: suggestionResults)
        }
    }
}

enum SearchSuggestions {
    static func fetch(for query: String) async -> [String] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: WebConstants.googleSuggestURL + encodedQuery),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [Any],
              payload.count > 1 else { return [] }
        return payload[1] as? [String] ?? []
    }
}
