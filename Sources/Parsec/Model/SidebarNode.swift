import AppKit
import Observation

@MainActor
@Observable
final class SidebarNode: Identifiable, @MainActor Codable {
    static let blankTabTitle = "Nueva pestaña"

    enum Kind: String, Codable {
        case tab
        case folder
        case split
    }

    let id: UUID
    var kind: Kind
    var title: String
    var url: URL?
    var children: [SidebarNode]
    var isExpanded: Bool
    var lastActiveAt: Date
    var iconSymbol: String?
    var conversationID: UUID?
    var customTitle: String?

    var page: WebPage?
    @ObservationIgnored var suspendedInteractionState: Any?

    enum CodingKeys: String, CodingKey {
        case id
        case _kind = "kind"
        case _title = "title"
        case _url = "url"
        case _children = "children"
        case _isExpanded = "isExpanded"
        case _lastActiveAt = "lastActiveAt"
        case _iconSymbol = "iconSymbol"
        case _conversationID = "conversationID"
        case _customTitle = "customTitle"
    }

    init(kind: Kind, title: String, url: URL? = nil, children: [SidebarNode] = [], isExpanded: Bool = true) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.url = url
        self.children = children
        self.isExpanded = isExpanded
        self.lastActiveAt = Date()
    }

    static func tab(url: URL?, title: String = "") -> SidebarNode {
        SidebarNode(kind: .tab, title: title, url: url)
    }

    static func folder(title: String, children: [SidebarNode] = []) -> SidebarNode {
        SidebarNode(kind: .folder, title: title, children: children)
    }

    static func split(panes: [SidebarNode]) -> SidebarNode {
        SidebarNode(kind: .split, title: "", children: panes)
    }

    func duplicated() -> SidebarNode {
        let copy = SidebarNode(kind: kind, title: title, url: url, children: children.map { $0.duplicated() }, isExpanded: isExpanded)
        copy.iconSymbol = iconSymbol
        copy.customTitle = customTitle
        return copy
    }

    var isTab: Bool { kind == .tab }
    var isFolder: Bool { kind == .folder }
    var isSplit: Bool { kind == .split }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        let liveTitle = page?.title ?? ""
        if !liveTitle.isEmpty { return liveTitle }
        if !title.isEmpty { return title }
        return displayHost.isEmpty ? Self.blankTabTitle : displayHost
    }

    var displayHost: String {
        let host = (page?.currentURL ?? url)?.host() ?? ""
        return host.replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    var allowsFaviconNetwork: Bool { !allTabs.contains { $0.page?.isEphemeral == true } }

    var liveURL: URL? { page?.currentURL ?? url }

    var allTabs: [SidebarNode] {
        guard isTab else { return children.flatMap(\.allTabs) }
        return [self]
    }

    var allFolders: [SidebarNode] {
        guard isFolder else { return [] }
        return [self] + children.flatMap(\.allFolders)
    }

    func contains(nodeID: UUID) -> Bool {
        id == nodeID || children.contains { $0.contains(nodeID: nodeID) }
    }
}

@MainActor
extension Array where Element == SidebarNode {
    var allTabs: [SidebarNode] { flatMap(\.allTabs) }

    func find(_ nodeID: UUID) -> SidebarNode? {
        for node in self {
            if node.id == nodeID { return node }
            if let match = node.children.find(nodeID) { return match }
        }
        return nil
    }

    func parent(of nodeID: UUID) -> SidebarNode? {
        for node in self {
            if node.children.contains(where: { $0.id == nodeID }) { return node }
            if let match = node.children.parent(of: nodeID) { return match }
        }
        return nil
    }

    @discardableResult
    mutating func removeNode(_ nodeID: UUID) -> SidebarNode? {
        if let index = firstIndex(where: { $0.id == nodeID }) {
            return remove(at: index)
        }
        for node in self {
            if let removed = node.children.removeNode(nodeID) { return removed }
        }
        return nil
    }
}
