import AppKit
import Observation
import SwiftUI
import WebKit

enum NodeContainer: Equatable {
    case favorites(profileID: UUID)
    case pinned(spaceID: UUID)
    case today(spaceID: UUID)
    case folder(nodeID: UUID)
    case split(nodeID: UUID)
}

enum NodeSection: Equatable {
    case favorites(profileID: UUID)
    case pinned(spaceID: UUID)
    case today(spaceID: UUID)
}

struct ClosedTab {
    let url: URL
    let spaceID: UUID
}

@MainActor
@Observable
final class BrowserStore {
    static let shared = BrowserStore()
    private static let defaultProfileName = "Personal"
    private static let defaultSpaceTitle = "Personal"
    private static let permissionKeySeparator = "|"

    var profiles: [Profile] = []
    var spaces: [Space] = []
    var settings = BrowserSettings()
    var lastSpaceID: UUID?

    @ObservationIgnored let history = HistoryStore()
    @ObservationIgnored var recentlyClosed: [ClosedTab] = []
    @ObservationIgnored var visibleNodeIDs: () -> Set<UUID> = { [] }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTimer: Timer?
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private let stateURL = StorageConstants.applicationSupportURL.appending(path: StorageConstants.stateFileName)

    func load() {
        LegacyContainerMigration.migrateIfNeeded()
        guard let data = try? Data(contentsOf: stateURL) else { return bootstrap() }
        guard let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            backUpUnreadableState()
            return bootstrap()
        }
        apply(state)
        backfillFolderIconsFromArc()
    }

    private func backfillFolderIconsFromArc() {
        guard !settings.hasBackfilledFolderIcons, settings.hasImportedFromArc, ArcImporter.isAvailable else { return }
        let iconsByTitle = ArcImporter.folderIconsByTitle()
        let folders = (spaces.flatMap(\.pinned) + profiles.flatMap(\.favorites)).flatMap(\.allFolders)
        folders.filter { $0.iconSymbol == nil }.forEach { $0.iconSymbol = iconsByTitle[$0.title] }
        settings.hasBackfilledFolderIcons = true
        saveNow()
    }

    private func backUpUnreadableState() {
        let backupName = "state-unreadable-\(Int(Date().timeIntervalSince1970)).json"
        try? FileManager.default.copyItem(at: stateURL, to: stateURL.deletingLastPathComponent().appending(path: backupName))
    }

    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: LifecycleConstants.saveDebounce)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        let state = PersistedState(profiles: profiles, spaces: spaces, selectedSpaceID: lastSpaceID, settings: settings)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func importFromArc() throws {
        let result = try ArcImporter.importSidebar()
        profiles.append(contentsOf: result.profiles)
        spaces.append(contentsOf: result.spaces)
        settings.hasImportedFromArc = true
        lastSpaceID = lastSpaceID ?? spaces.first?.id
        saveNow()
    }

    private func apply(_ state: PersistedState) {
        profiles = state.profiles
        spaces = state.spaces
        settings = state.settings
        lastSpaceID = state.selectedSpaceID ?? spaces.first?.id
        ensureAtLeastOneSpace()
        settings.restoresPreviousSession ? keepRestoredTabsAlive() : discardPreviousSessionTabs()
    }

    private func keepRestoredTabsAlive() {
        let launchDate = Date()
        for node in spaces.flatMap(\.today) {
            node.lastActiveAt = launchDate
            node.allTabs.forEach { $0.lastActiveAt = launchDate }
        }
    }

    private func discardPreviousSessionTabs() {
        for space in spaces {
            let selectedWasToday = space.selectedNodeID.map { space.today.find($0) != nil } ?? false
            if selectedWasToday { space.selectedNodeID = nil }
            space.today.removeAll()
        }
    }

    private func bootstrap() {
        if ArcImporter.isAvailable, (try? importFromArc()) != nil, !spaces.isEmpty { return }
        ensureAtLeastOneSpace()
        saveNow()
    }

    private func ensureAtLeastOneSpace() {
        guard spaces.isEmpty else { return }
        let profile = profiles.first ?? Profile(name: Self.defaultProfileName)
        if profiles.isEmpty { profiles.append(profile) }
        let space = Space(title: Self.defaultSpaceTitle, profileID: profile.id)
        spaces.append(space)
        lastSpaceID = space.id
    }
}

extension BrowserStore {
    func space(id: UUID?) -> Space? {
        spaces.first { $0.id == id }
    }

    func profile(id: UUID?) -> Profile? {
        profiles.first { $0.id == id }
    }

    func profile(for space: Space) -> Profile? {
        profile(id: space.profileID)
    }

    func section(of nodeID: UUID) -> NodeSection? {
        if let profile = profiles.first(where: { $0.favorites.find(nodeID) != nil }) { return .favorites(profileID: profile.id) }
        for space in spaces {
            if space.pinned.find(nodeID) != nil { return .pinned(spaceID: space.id) }
            if space.today.find(nodeID) != nil { return .today(spaceID: space.id) }
        }
        return nil
    }

    func isPinnedOrFavorite(_ nodeID: UUID) -> Bool {
        switch section(of: nodeID) {
        case .favorites, .pinned: true
        default: false
        }
    }

    func profileID(forNode nodeID: UUID) -> UUID? {
        switch section(of: nodeID) {
        case .favorites(let profileID): profileID
        case .pinned(let spaceID), .today(let spaceID): space(id: spaceID)?.profileID
        case nil: nil
        }
    }

    func node(_ nodeID: UUID) -> SidebarNode? {
        for profile in profiles {
            if let match = profile.favorites.find(nodeID) { return match }
        }
        for space in spaces {
            if let match = space.allNodes.find(nodeID) { return match }
        }
        return nil
    }

    var allTabNodes: [SidebarNode] {
        profiles.flatMap(\.favorites.allTabs) + spaces.flatMap(\.allNodes.allTabs)
    }

    func spaceIDs(usingProfile profileID: UUID) -> [UUID] {
        spaces.filter { $0.profileID == profileID }.map(\.id)
    }
}

extension BrowserStore {
    private static var rowAnimation: Animation { Motion.spring(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }

    @discardableResult
    func detach(_ nodeID: UUID) -> SidebarNode? {
        var detached: SidebarNode?
        withAnimation(Self.rowAnimation) {
            for profile in profiles {
                if let removed = profile.favorites.removeNode(nodeID) { return detached = collapseSplits(afterRemoving: removed) }
            }
            for space in spaces {
                if let removed = space.pinned.removeNode(nodeID) { return detached = collapseSplits(afterRemoving: removed) }
                if let removed = space.today.removeNode(nodeID) { return detached = collapseSplits(afterRemoving: removed) }
            }
        }
        return detached
    }

    func insert(_ node: SidebarNode, into container: NodeContainer, at index: Int? = nil) {
        let profileBefore = node.page?.profileID
        withAnimation(Self.rowAnimation) {
            modifyChildren(of: container) { children in
                let insertionIndex = min(index ?? children.count, children.count)
                children.insert(node, at: insertionIndex)
            }
        }
        let profileAfter = profileID(forNode: node.id)
        if let profileBefore, profileBefore != profileAfter { unloadPages(in: node) }
        saveSoon()
    }

    func move(_ nodeID: UUID, into container: NodeContainer, at index: Int? = nil) {
        if self.container(of: nodeID) == container {
            withAnimation(Self.rowAnimation) {
                modifyChildren(of: container) { children in
                    guard let sourceIndex = children.firstIndex(where: { $0.id == nodeID }) else { return }
                    let node = children.remove(at: sourceIndex)
                    children.insert(node, at: min(max(index ?? children.count, 0), children.count))
                }
            }
            saveSoon()
            return
        }
        guard !isDescendant(container, of: nodeID), let node = detach(nodeID) else { return }
        insert(node, into: container, at: index)
    }

    func index(of nodeID: UUID, in container: NodeContainer) -> Int? {
        var foundIndex: Int?
        modifyChildren(of: container) { children in foundIndex = children.firstIndex { $0.id == nodeID } }
        return foundIndex
    }

    func container(of nodeID: UUID) -> NodeContainer? {
        for profile in profiles {
            if profile.favorites.contains(where: { $0.id == nodeID }) { return .favorites(profileID: profile.id) }
            if let parent = profile.favorites.parent(of: nodeID) { return nestedContainer(parent) }
        }
        for space in spaces {
            if space.pinned.contains(where: { $0.id == nodeID }) { return .pinned(spaceID: space.id) }
            if space.today.contains(where: { $0.id == nodeID }) { return .today(spaceID: space.id) }
            if let parent = space.allNodes.parent(of: nodeID) { return nestedContainer(parent) }
        }
        return nil
    }

    func remove(_ nodeID: UUID) {
        guard let removed = detach(nodeID) else { return }
        rememberClosed(removed)
        unloadPages(in: removed)
        saveSoon()
    }

    func rememberClosed(_ node: SidebarNode) {
        guard let spaceID = spaceContaining(node) ?? lastSpaceID else { return }
        let closedTabs = node.allTabs.compactMap { tab in tab.liveURL.map { ClosedTab(url: $0, spaceID: spaceID) } }
        recentlyClosed.append(contentsOf: closedTabs)
        recentlyClosed = Array(recentlyClosed.suffix(LifecycleConstants.maxRecentlyClosed))
    }

    private func spaceContaining(_ node: SidebarNode) -> UUID? {
        spaces.first { $0.allNodes.find(node.id) != nil }?.id
    }

    private func nestedContainer(_ parent: SidebarNode) -> NodeContainer {
        parent.isSplit ? .split(nodeID: parent.id) : .folder(nodeID: parent.id)
    }

    private func isDescendant(_ container: NodeContainer, of nodeID: UUID) -> Bool {
        switch container {
        case .folder(let targetID), .split(let targetID): node(nodeID)?.contains(nodeID: targetID) ?? false
        default: false
        }
    }

    private func modifyChildren(of container: NodeContainer, _ body: (inout [SidebarNode]) -> Void) {
        switch container {
        case .favorites(let profileID):
            guard let profile = profile(id: profileID) else { return }
            body(&profile.favorites)
        case .pinned(let spaceID):
            guard let space = space(id: spaceID) else { return }
            body(&space.pinned)
        case .today(let spaceID):
            guard let space = space(id: spaceID) else { return }
            body(&space.today)
        case .folder(let nodeID), .split(let nodeID):
            guard let parent = node(nodeID) else { return }
            body(&parent.children)
        }
    }

    private func collapseSplits(afterRemoving removed: SidebarNode) -> SidebarNode {
        let lonelySplits = (profiles.flatMap(\.favorites) + spaces.flatMap(\.allNodes)).flatMap(splitNodes).filter { $0.children.count < 2 }
        for split in lonelySplits {
            let survivor = split.children.first
            guard let container = container(of: split.id), let splitIndex = index(of: split.id, in: container) else { continue }
            modifyChildren(of: container) { children in
                children.remove(at: splitIndex)
                if let survivor { children.insert(survivor, at: splitIndex) }
            }
        }
        return removed
    }

    private func splitNodes(in node: SidebarNode) -> [SidebarNode] {
        (node.isSplit ? [node] : []) + node.children.flatMap(splitNodes)
    }
}

extension BrowserStore {
    func addSpace(title: String, profileID: UUID, theme: SpaceTheme = .standard) -> Space {
        let space = Space(title: title, profileID: profileID, theme: theme)
        spaces.append(space)
        saveSoon()
        return space
    }

    func addProfile(name: String) -> Profile {
        let profile = Profile(name: name)
        profiles.append(profile)
        saveSoon()
        return profile
    }

    func deleteSpace(_ spaceID: UUID) {
        guard spaces.count > 1, let space = space(id: spaceID) else { return }
        space.allNodes.forEach(unloadPages)
        spaces.removeAll { $0.id == spaceID }
        if lastSpaceID == spaceID { lastSpaceID = spaces.first?.id }
        saveSoon()
    }

    func isBlockerDisabled(host: String) -> Bool {
        settings.blockerDisabledHosts.contains(host)
    }

    func setBlocker(enabled: Bool, host: String) {
        if enabled {
            settings.blockerDisabledHosts.remove(host)
        } else {
            settings.blockerDisabledHosts.insert(host)
        }
        saveSoon()
    }

    func permissionDecision(profileID: UUID, host: String, kind: PermissionKind) -> Bool? {
        settings.sitePermissions[permissionKey(profileID: profileID, host: host, kind: kind)]
    }

    func setPermission(_ isGranted: Bool, profileID: UUID, host: String, kind: PermissionKind) {
        settings.sitePermissions[permissionKey(profileID: profileID, host: host, kind: kind)] = isGranted
        saveSoon()
    }

    func permissions(profileID: UUID, host: String) -> [(kind: PermissionKind, isGranted: Bool)] {
        settings.sitePermissions.compactMap { key, decision in
            let parts = key.components(separatedBy: Self.permissionKeySeparator)
            guard parts.count == 3, parts[0] == profileID.uuidString,
                  Self.permissionHost(parts[1]) == host, let kind = PermissionKind(rawValue: parts[2]) else { return nil }
            return (kind, decision)
        }
    }

    private static func permissionHost(_ origin: String) -> String {
        URL(string: origin)?.host ?? origin
    }

    func resetPermissions(profileID: UUID, host: String) {
        settings.sitePermissions = settings.sitePermissions.filter { key, _ in
            let parts = key.components(separatedBy: Self.permissionKeySeparator)
            return parts.count != 3 || parts[0] != profileID.uuidString || Self.permissionHost(parts[1]) != host
        }
        saveSoon()
    }

    var permissionEntries: [SitePermissionEntry] {
        settings.sitePermissions.compactMap { key, isGranted in
            let parts = key.components(separatedBy: Self.permissionKeySeparator)
            guard parts.count == 3, let kind = PermissionKind(rawValue: parts[2]) else { return nil }
            return SitePermissionEntry(key: key, host: parts[1], kind: kind, isGranted: isGranted)
        }
        .sorted { $0.host < $1.host }
    }

    func removePermission(_ entry: SitePermissionEntry) {
        settings.sitePermissions[entry.key] = nil
        saveSoon()
    }

    private func permissionKey(profileID: UUID, host: String, kind: PermissionKind) -> String {
        [profileID.uuidString, host, kind.rawValue].joined(separator: Self.permissionKeySeparator)
    }
}

extension BrowserStore {
    @discardableResult
    func ensurePage(for node: SidebarNode, profileID: UUID, isPrivate: Bool, configuration: WKWebViewConfiguration? = nil) -> WebPage {
        if let existing = node.page, existing.profileID == profileID, existing.isPrivate == isPrivate { return existing }
        if node.page != nil { unloadPage(node) }
        let page = WebPage(profileID: profileID, isPrivate: isPrivate, configuration: configuration)
        page.node = node
        page.isAutoPeekSource = isPinnedOrFavorite(node.id)
        node.page = page
        if configuration == nil, let url = node.url { page.load(url) }
        return page
    }

    func unloadPages(in node: SidebarNode) {
        node.allTabs.forEach(unloadPage)
    }

    func unloadPage(_ node: SidebarNode) {
        node.page?.tearDown()
        node.page = nil
    }

    func pageDidFinishNavigation(_ page: WebPage) {
        guard let node = page.node, let url = page.currentURL else { return }
        let isTodayTab: Bool
        switch section(of: node.id) {
        case .today: isTodayTab = true
        default: isTodayTab = false
        }
        guard isTodayTab || node.url == nil else { return }
        node.url = url
        node.title = page.title
        saveSoon()
    }

    func startLifecycle() {
        lifecycleTimer = Timer.scheduledTimer(withTimeInterval: LifecycleConstants.lifecycleTickInterval, repeats: true) { _ in
            Task { @MainActor in BrowserStore.shared.runLifecycleTick() }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            Task { @MainActor in BrowserStore.shared.relieveMemoryPressure() }
        }
        source.resume()
        memoryPressureSource = source
    }

    func runLifecycleTick() {
        let visibleIDs = visibleNodeIDs()
        let now = Date()
        let suspendAfter = TimeInterval(settings.suspendAfterMinutes * 60)
        for node in allTabNodes where settings.suspendAfterMinutes > 0 && node.page != nil && !visibleIDs.contains(node.id) {
            guard now.timeIntervalSince(node.lastActiveAt) > suspendAfter else { continue }
            suspendIfIdle(node)
        }
        archiveStaleTodayTabs(visibleIDs: visibleIDs, now: now)
    }

    func relieveMemoryPressure() {
        let visibleIDs = visibleNodeIDs()
        let loadedNodes = allTabNodes
            .filter { $0.page != nil && !visibleIDs.contains($0.id) }
            .sorted { $0.lastActiveAt < $1.lastActiveAt }
        loadedNodes.prefix(max(1, loadedNodes.count / 2)).forEach(suspendIfIdle)
    }

    private func suspendIfIdle(_ node: SidebarNode) {
        guard let page = node.page, !page.isCapturingMedia, !page.isLoading, page.agentActivity == nil else { return }
        let lastActiveAt = node.lastActiveAt
        Task { [weak node, weak page] in
            guard let node, let page, await isIdle(page), node.page === page, node.lastActiveAt == lastActiveAt,
                  !visibleNodeIDs().contains(node.id) else { return }
            unloadPage(node)
        }
    }

    private func isIdle(_ page: WebPage) async -> Bool {
        guard !page.isCapturingMedia, !page.isLoading, page.agentActivity == nil else { return false }
        let state = await withCheckedContinuation { continuation in
            page.webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        return state != .playing && !page.isCapturingMedia && !page.isLoading && page.agentActivity == nil
    }

    private func archiveStaleTodayTabs(visibleIDs: Set<UUID>, now: Date) {
        for space in spaces {
            let archiveInterval = profile(for: space)?.archiveInterval ?? LifecycleConstants.archiveTodayAfter
            let staleNodes = space.today.filter { node in
                let isStale = now.timeIntervalSince(node.lastActiveAt) > archiveInterval
                let isVisible = node.allTabs.contains { visibleIDs.contains($0.id) } || visibleIDs.contains(node.id)
                let isPlaying = node.allTabs.contains { $0.page?.isCapturingMedia == true }
                return isStale && !isVisible && !isPlaying
            }
            guard !staleNodes.isEmpty else { continue }
            for node in staleNodes {
                let lastActiveAt = node.lastActiveAt
                Task { [weak node, weak space] in
                    guard let node, let space else { return }
                    let pages = node.allTabs.compactMap(\.page)
                    for page in pages {
                        guard await isIdle(page) else { return }
                    }
                    let currentIDs = visibleNodeIDs()
                    let isVisible = currentIDs.contains(node.id) || node.allTabs.contains { currentIDs.contains($0.id) }
                    let hasChangedPages = node.allTabs.compactMap(\.page).contains { current in !pages.contains { $0 === current } }
                    guard node.lastActiveAt == lastActiveAt, !isVisible, !hasChangedPages,
                          space.today.contains(where: { $0 === node }) else { return }
                    unloadPages(in: node)
                    space.today.removeAll { $0 === node }
                    saveSoon()
                }
            }
        }
    }
}

struct SitePermissionEntry: Identifiable {
    let key: String
    let host: String
    let kind: PermissionKind
    let isGranted: Bool
    var id: String { key }
}
