import SwiftUI
import Observation

struct ThemeColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
    }

    private static let matchTolerance = 0.035

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    func matches(_ other: ThemeColor) -> Bool {
        abs(red - other.red) < Self.matchTolerance && abs(green - other.green) < Self.matchTolerance && abs(blue - other.blue) < Self.matchTolerance
    }
}

enum SpaceAppearance: String, Codable, CaseIterable {
    case auto
    case light
    case dark
}

struct SpaceTheme: Codable, Hashable {
    static let maxColors = 3
    static let standard = SpaceTheme(colors: [ThemeColor(red: 0.8, green: 0.8, blue: 0.82)], grain: 0.6, transparency: 0.25)
    static let prism = SpaceTheme(colors: [
        ThemeColor(red: 0.18, green: 0.12, blue: 0.49),
        ThemeColor(red: 0.01, green: 0.29, blue: 0.25),
        ThemeColor(red: 0.06, green: 0.16, blue: 0.49),
    ], grain: 0, transparency: 0)

    var colors: [ThemeColor]
    var grain: Double
    var transparency: Double
    var appearance = SpaceAppearance.auto
    var vibrancy = 0.6
    var sidebarColor: ThemeColor? = nil

    init(colors: [ThemeColor], grain: Double, transparency: Double) {
        self.colors = colors
        self.grain = grain
        self.transparency = transparency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colors = try container.decode([ThemeColor].self, forKey: .colors)
        grain = try container.decode(Double.self, forKey: .grain)
        transparency = try container.decode(Double.self, forKey: .transparency)
        appearance = try container.decodeIfPresent(SpaceAppearance.self, forKey: .appearance) ?? .auto
        vibrancy = try container.decodeIfPresent(Double.self, forKey: .vibrancy) ?? 0.6
        sidebarColor = try container.decodeIfPresent(ThemeColor.self, forKey: .sidebarColor)
    }

    var isDark: Bool {
        let averageLuminance = colors.map(\.luminance).reduce(0, +) / Double(max(colors.count, 1))
        return averageLuminance < 0.55
    }
}

@MainActor
@Observable
final class Profile: Identifiable, @MainActor Codable {
    static let defaultArchiveHours = 12

    let id: UUID
    var name: String
    var favorites: [SidebarNode]
    var iconSymbol: String?
    var accentColor: ThemeColor?
    var archiveAfterHours: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case _name = "name"
        case _favorites = "favorites"
        case _iconSymbol = "iconSymbol"
        case _accentColor = "accentColor"
        case _archiveAfterHours = "archiveAfterHours"
    }

    var archiveInterval: TimeInterval {
        TimeInterval(archiveAfterHours ?? Self.defaultArchiveHours) * 60 * 60
    }

    init(name: String, favorites: [SidebarNode] = []) {
        self.id = UUID()
        self.name = name
        self.favorites = favorites
    }
}

@MainActor
@Observable
final class Space: Identifiable, @MainActor Codable {
    let id: UUID
    var title: String
    var profileID: UUID
    var theme: SpaceTheme
    var pinned: [SidebarNode]
    var today: [SidebarNode]
    var selectedNodeID: UUID?
    var iconSymbol: String?

    enum CodingKeys: String, CodingKey {
        case id
        case _iconSymbol = "iconSymbol"
        case _title = "title"
        case _profileID = "profileID"
        case _theme = "theme"
        case _pinned = "pinned"
        case _today = "today"
        case _selectedNodeID = "selectedNodeID"
    }

    init(title: String, profileID: UUID, theme: SpaceTheme = .standard, pinned: [SidebarNode] = [], today: [SidebarNode] = []) {
        self.id = UUID()
        self.title = title
        self.profileID = profileID
        self.theme = theme
        self.pinned = pinned
        self.today = today
    }

    var allNodes: [SidebarNode] { pinned + today }
}

enum LinkOpeningBehavior: String, Codable, CaseIterable {
    case newTab
    case miniWindow

    var title: String {
        switch self {
        case .newTab: "Pestaña nueva"
        case .miniWindow: "Ventana flotante"
        }
    }
}

enum SidebarLayout: String, Codable, CaseIterable {
    case sidebar
    case topTabs
}

struct BrowserSettings: Codable {
    static let defaultSidebarWidth: Double = 264
    static let legacySuspendAfterMinutes = 30
    static let defaultSuspendAfterMinutes = 0
    static let sidebarWidthRange: ClosedRange<Double> = 210...460

    var layout: SidebarLayout = .sidebar
    var isSidebarPinned = false
    var sidebarWidth = defaultSidebarWidth
    var showsSearchSuggestions = true
    var blockerDisabledHosts: Set<String> = []
    var passwordNeverHosts: Set<String> = []
    var autofillsPasswords = true
    var hasImportedFromArc = false
    var sitePermissions: [String: Bool] = [:]
    var assistantIncludesPage = true
    var hasBackfilledFolderIcons = false
    var assistantProvider = AssistantProviderKind.claudeCode
    var assistantModels: [String: String] = [:]
    var assistantUsesWebSearch = false
    var assistantConnectors: Set<String> = []
    var hasSeenWelcome = false
    var miniPopupEnabled = false
    var miniPopupHotKey = MiniPopupHotKey.standard
    var shortcutOverrides: [String: String] = [:]
    var blockedSites: [String] = []
    var docsProvider = DocsProvider.googleDocs
    var downloadFolderPath: String?
    var playsSounds = true
    var showsFullURL = false
    var opensExternalLinksInLittleWindow = true
    var suspendAfterMinutes = defaultSuspendAfterMinutes
    var customProviderName = "Personalizado"
    var customProviderBaseURL = "http://localhost:11434/v1"
    var developerMode = false
    var warnsAboutFraudulentSites = true
    var warnsBeforeRiskyDownloads = true
    var userProfile = UserProfile()
    var savesConversations = true
    var commandBarActions = QuickAction.defaults
    var commandBarShowsFavorites = true
    var commandBarShowsRecentTabs = true
    var commandBarShowsConversations = true
    var agentUsesSessions = false
    var edgeRevealDelayMilliseconds = 200
    var confirmsBeforeQuit = false
    var restoresPreviousSession = true
    var autoPictureInPicture = true
    var appIconID = AppIconConstants.defaultID
    var linkOpening = LinkOpeningBehavior.newTab
    var showsLinkPreviews = false
    var linkPreviewDelayMilliseconds = 700
    var linkPreviewSize = LinkPreviewSize.medium
    var hidesGoogleOneTap = true
    var customColors: [ThemeColor] = []
    var liquidGlass = 1.0
    var surfaceOpacity = 1.0
    var folderIconColor: ThemeColor? = nil

    init() {}

    func isBlocked(host: String) -> Bool {
        blockedSites.contains { blocked in host == blocked || host.hasSuffix("." + blocked) }
    }

    func assistantModel(for provider: AssistantProviderKind) -> String {
        assistantModels[provider.rawValue] ?? provider.defaultModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrowserSettings()
        layout = try container.decodeIfPresent(SidebarLayout.self, forKey: .layout) ?? defaults.layout
        isSidebarPinned = try container.decodeIfPresent(Bool.self, forKey: .isSidebarPinned) ?? defaults.isSidebarPinned
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? defaults.sidebarWidth
        showsSearchSuggestions = try container.decodeIfPresent(Bool.self, forKey: .showsSearchSuggestions) ?? defaults.showsSearchSuggestions
        blockerDisabledHosts = try container.decodeIfPresent(Set<String>.self, forKey: .blockerDisabledHosts) ?? defaults.blockerDisabledHosts
        passwordNeverHosts = try container.decodeIfPresent(Set<String>.self, forKey: .passwordNeverHosts) ?? defaults.passwordNeverHosts
        autofillsPasswords = try container.decodeIfPresent(Bool.self, forKey: .autofillsPasswords) ?? defaults.autofillsPasswords
        hasImportedFromArc = try container.decodeIfPresent(Bool.self, forKey: .hasImportedFromArc) ?? defaults.hasImportedFromArc
        sitePermissions = try container.decodeIfPresent([String: Bool].self, forKey: .sitePermissions) ?? defaults.sitePermissions
        assistantIncludesPage = try container.decodeIfPresent(Bool.self, forKey: .assistantIncludesPage) ?? defaults.assistantIncludesPage
        hasBackfilledFolderIcons = try container.decodeIfPresent(Bool.self, forKey: .hasBackfilledFolderIcons) ?? defaults.hasBackfilledFolderIcons
        assistantProvider = try container.decodeIfPresent(AssistantProviderKind.self, forKey: .assistantProvider) ?? defaults.assistantProvider
        assistantModels = try container.decodeIfPresent([String: String].self, forKey: .assistantModels) ?? defaults.assistantModels
        assistantUsesWebSearch = try container.decodeIfPresent(Bool.self, forKey: .assistantUsesWebSearch) ?? defaults.assistantUsesWebSearch
        assistantConnectors = try container.decodeIfPresent(Set<String>.self, forKey: .assistantConnectors) ?? defaults.assistantConnectors
        hasSeenWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? defaults.hasSeenWelcome
        miniPopupEnabled = try container.decodeIfPresent(Bool.self, forKey: .miniPopupEnabled) ?? defaults.miniPopupEnabled
        miniPopupHotKey = try container.decodeIfPresent(MiniPopupHotKey.self, forKey: .miniPopupHotKey) ?? defaults.miniPopupHotKey
        shortcutOverrides = try container.decodeIfPresent([String: String].self, forKey: .shortcutOverrides) ?? defaults.shortcutOverrides
        blockedSites = try container.decodeIfPresent([String].self, forKey: .blockedSites) ?? defaults.blockedSites
        docsProvider = try container.decodeIfPresent(DocsProvider.self, forKey: .docsProvider) ?? defaults.docsProvider
        downloadFolderPath = try container.decodeIfPresent(String.self, forKey: .downloadFolderPath)
        playsSounds = try container.decodeIfPresent(Bool.self, forKey: .playsSounds) ?? defaults.playsSounds
        showsFullURL = try container.decodeIfPresent(Bool.self, forKey: .showsFullURL) ?? defaults.showsFullURL
        opensExternalLinksInLittleWindow = try container.decodeIfPresent(Bool.self, forKey: .opensExternalLinksInLittleWindow) ?? defaults.opensExternalLinksInLittleWindow
        let storedSuspendMinutes = try container.decodeIfPresent(Int.self, forKey: .suspendAfterMinutes)
        suspendAfterMinutes = storedSuspendMinutes == Self.legacySuspendAfterMinutes ? defaults.suspendAfterMinutes : storedSuspendMinutes ?? defaults.suspendAfterMinutes
        customProviderName = try container.decodeIfPresent(String.self, forKey: .customProviderName) ?? defaults.customProviderName
        customProviderBaseURL = try container.decodeIfPresent(String.self, forKey: .customProviderBaseURL) ?? defaults.customProviderBaseURL
        developerMode = try container.decodeIfPresent(Bool.self, forKey: .developerMode) ?? defaults.developerMode
        warnsAboutFraudulentSites = try container.decodeIfPresent(Bool.self, forKey: .warnsAboutFraudulentSites) ?? defaults.warnsAboutFraudulentSites
        warnsBeforeRiskyDownloads = try container.decodeIfPresent(Bool.self, forKey: .warnsBeforeRiskyDownloads) ?? defaults.warnsBeforeRiskyDownloads
        userProfile = try container.decodeIfPresent(UserProfile.self, forKey: .userProfile) ?? defaults.userProfile
        savesConversations = try container.decodeIfPresent(Bool.self, forKey: .savesConversations) ?? defaults.savesConversations
        commandBarActions = try container.decodeIfPresent([QuickAction].self, forKey: .commandBarActions) ?? defaults.commandBarActions
        commandBarShowsFavorites = try container.decodeIfPresent(Bool.self, forKey: .commandBarShowsFavorites) ?? defaults.commandBarShowsFavorites
        commandBarShowsRecentTabs = try container.decodeIfPresent(Bool.self, forKey: .commandBarShowsRecentTabs) ?? defaults.commandBarShowsRecentTabs
        commandBarShowsConversations = try container.decodeIfPresent(Bool.self, forKey: .commandBarShowsConversations) ?? defaults.commandBarShowsConversations
        agentUsesSessions = try container.decodeIfPresent(Bool.self, forKey: .agentUsesSessions) ?? defaults.agentUsesSessions
        edgeRevealDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .edgeRevealDelayMilliseconds) ?? defaults.edgeRevealDelayMilliseconds
        confirmsBeforeQuit = try container.decodeIfPresent(Bool.self, forKey: .confirmsBeforeQuit) ?? defaults.confirmsBeforeQuit
        restoresPreviousSession = try container.decodeIfPresent(Bool.self, forKey: .restoresPreviousSession) ?? defaults.restoresPreviousSession
        autoPictureInPicture = try container.decodeIfPresent(Bool.self, forKey: .autoPictureInPicture) ?? defaults.autoPictureInPicture
        appIconID = try container.decodeIfPresent(String.self, forKey: .appIconID) ?? defaults.appIconID
        linkOpening = try container.decodeIfPresent(LinkOpeningBehavior.self, forKey: .linkOpening) ?? defaults.linkOpening
        showsLinkPreviews = try container.decodeIfPresent(Bool.self, forKey: .showsLinkPreviews) ?? defaults.showsLinkPreviews
        linkPreviewDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .linkPreviewDelayMilliseconds) ?? defaults.linkPreviewDelayMilliseconds
        linkPreviewSize = try container.decodeIfPresent(LinkPreviewSize.self, forKey: .linkPreviewSize) ?? defaults.linkPreviewSize
        hidesGoogleOneTap = try container.decodeIfPresent(Bool.self, forKey: .hidesGoogleOneTap) ?? defaults.hidesGoogleOneTap
        customColors = try container.decodeIfPresent([ThemeColor].self, forKey: .customColors) ?? []
        liquidGlass = try container.decodeIfPresent(Double.self, forKey: .liquidGlass) ?? defaults.liquidGlass
        surfaceOpacity = try container.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? defaults.surfaceOpacity
        folderIconColor = try container.decodeIfPresent(ThemeColor.self, forKey: .folderIconColor)
    }
}

struct UserProfile: Codable, Equatable {
    var name = ""
    var occupation = ""
    var location = ""
    var languages = ""
    var about = ""
    var assistantInstructions = ""
    var sharesWithAssistant = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        occupation = try container.decodeIfPresent(String.self, forKey: .occupation) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        languages = try container.decodeIfPresent(String.self, forKey: .languages) ?? ""
        about = try container.decodeIfPresent(String.self, forKey: .about) ?? ""
        assistantInstructions = try container.decodeIfPresent(String.self, forKey: .assistantInstructions) ?? ""
        sharesWithAssistant = try container.decodeIfPresent(Bool.self, forKey: .sharesWithAssistant) ?? true
    }

    var firstName: String? {
        name.split(separator: " ").first.map(String.init)
    }

    var assistantContext: String {
        guard sharesWithAssistant else { return "" }
        let facts = [
            ("Nombre", name), ("A qué se dedica", occupation), ("Dónde vive", location),
            ("Idiomas", languages), ("Sobre el usuario", about), ("Cómo quiere que respondas", assistantInstructions),
        ]
        .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { "\($0.0): \($0.1)" }
        guard !facts.isEmpty else { return "" }
        return "\n<user_profile>\n" + facts.joined(separator: "\n") + "\n</user_profile>\nUsa este perfil para personalizar tus respuestas cuando sea relevante."
    }
}

@MainActor
struct PersistedState: @MainActor Codable {
    var profiles: [Profile]
    var spaces: [Space]
    var selectedSpaceID: UUID?
    var settings: BrowserSettings
}

enum DocsProvider: String, Codable, CaseIterable, Identifiable {
    case googleDocs
    case notion
    case word

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleDocs: "Google Docs"
        case .notion: "Notion"
        case .word: "Microsoft Word"
        }
    }

    var newDocumentURL: URL {
        switch self {
        case .googleDocs: URL(string: "https://docs.new")!
        case .notion: URL(string: "https://www.notion.so/new")!
        case .word: URL(string: "https://www.office.com/launch/word")!
        }
    }

    var signInURL: URL {
        switch self {
        case .googleDocs: URL(string: "https://accounts.google.com/ServiceLogin?continue=https://docs.google.com")!
        case .notion: URL(string: "https://www.notion.so/login")!
        case .word: URL(string: "https://login.microsoftonline.com")!
        }
    }

    var logoURL: URL {
        switch self {
        case .googleDocs: URL(string: "https://docs.google.com")!
        case .notion: URL(string: "https://www.notion.so")!
        case .word: URL(string: "https://www.office.com")!
        }
    }
}
