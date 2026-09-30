import AppKit
import Observation
import WebKit

struct PermissionRequest: Identifiable {
    let id = UUID()
    let host: String
    let kind: PermissionKind
    let profileID: UUID
    let continuation: CheckedContinuation<Bool, Never>
}

struct PasswordOffer: Identifiable {
    let id = UUID()
    let host: String
    let username: String
    let password: String
}

struct PeekState: Identifiable {
    let id = UUID()
    let node: SidebarNode
}

enum RevealEdge {
    case sidebar
    case assistant
}

enum CommandBarMode: Equatable {
    case newTab
    case navigateCurrent
    case navigate(nodeID: UUID)
}

@MainActor
@Observable
final class WindowModel: WebPageHost {
    private static let privateSpaceTitle = "Privado"
    private static let privateTheme = SpaceTheme(colors: [ThemeColor(red: 0.18, green: 0.16, blue: 0.24)], grain: 0.5, transparency: 0.2)
    private static let zoomStep = 0.1
    private static let minimumZoom = 0.3
    private static let maximumZoom = 3.0

    let store = BrowserStore.shared
    let isPrivate: Bool
    let privateProfileID = UUID()
    private let privateSpace: Space?

    @ObservationIgnored weak var window: NSWindow?
    var selectedSpaceID: UUID
    var isSidebarHovering = false
    var commandBar: CommandBarModel?
    var peek: PeekState?
    var isFindBarVisible = false
    var findHasNoMatch = false
    var toast: String?
    var permissionRequest: PermissionRequest?
    var passwordOffer: PasswordOffer?
    var credentialChoices: [SavedCredential] = []
    var focusedPaneID: UUID?
    var isThemeEditorPresented = false
    var isNewSpacePresented = false
    var isSitePopoverPresented = false
    var isAssistantPresented = false
    var isAssistantHovering = false
    var folderIconEditingID: UUID?
    var renamingNodeID: UUID?
    var spaceIconEditingID: UUID?
    var isWelcomePresented = false
    var agents: [AssistantModel] = []
    var activeAgentID: UUID?
    var pageConversations: [UUID: AssistantModel] = [:]
    var isHistoryPresented = false
    var linkPreview: LinkPreviewState?
    @ObservationIgnored private var previousSelectionID: UUID?
    @ObservationIgnored private var pendingReveals: [RevealEdge: Task<Void, Never>] = [:]
    @ObservationIgnored private var linkPreviewShowTask: Task<Void, Never>?
    @ObservationIgnored private var linkPreviewDismissTask: Task<Void, Never>?

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        if isPrivate {
            let space = Space(title: Self.privateSpaceTitle, profileID: UUID(), theme: Self.privateTheme)
            privateSpace = space
            selectedSpaceID = space.id
        } else {
            privateSpace = nil
            selectedSpaceID = BrowserStore.shared.lastSpaceID ?? BrowserStore.shared.spaces[0].id
            isWelcomePresented = !BrowserStore.shared.settings.hasSeenWelcome
        }
        let firstAgent = AssistantModel(windowModel: self)
        agents = [firstAgent]
        activeAgentID = firstAgent.id
    }

    var spaces: [Space] {
        privateSpace.map { [$0] } ?? store.spaces
    }

    var currentSpace: Space {
        spaces.first { $0.id == selectedSpaceID } ?? spaces[0]
    }

    var currentSpaceIndex: Int {
        spaces.firstIndex { $0.id == selectedSpaceID } ?? 0
    }

    var profileID: UUID {
        isPrivate ? privateProfileID : currentSpace.profileID
    }

    var favorites: [SidebarNode] {
        isPrivate ? [] : store.profile(id: currentSpace.profileID)?.favorites ?? []
    }

    var selectedNode: SidebarNode? {
        guard let selectedID = currentSpace.selectedNodeID else { return nil }
        return favorites.find(selectedID) ?? currentSpace.allNodes.find(selectedID)
    }

    var activeTab: SidebarNode? {
        guard let selectedNode else { return nil }
        guard selectedNode.isSplit else { return selectedNode }
        return selectedNode.children.first { $0.id == focusedPaneID } ?? selectedNode.children.first
    }

    var isShowingStartPage: Bool {
        guard let selectedNode, !selectedNode.isSplit else { return selectedNode == nil }
        return selectedNode.url == nil && selectedNode.page?.currentURL == nil
    }

    var activePage: WebPage? {
        activeTab?.page
    }

    var isSidebarPinned: Bool {
        store.settings.isSidebarPinned
    }

    var sidebarWidth: CGFloat {
        CGFloat(store.settings.sidebarWidth)
    }

    var visibleNodeIDs: Set<UUID> {
        var identifiers: Set<UUID> = []
        if let selectedNode { identifiers.formUnion([selectedNode.id] + selectedNode.children.map(\.id)) }
        if let peek { identifiers.insert(peek.node.id) }
        return identifiers
    }

    var isSelectedNodeFavorite: Bool {
        guard let selectedNode else { return false }
        return favorites.find(selectedNode.id) != nil
    }
}

extension WindowModel {
    func select(_ node: SidebarNode) {
        guard !node.isFolder else { return }
        if currentSpace.selectedNodeID != node.id {
            handOffPictureInPicture(from: selectedNode, to: node)
            dismissLinkPreview()
        }
        restoreConversation(for: node)
        if currentSpace.selectedNodeID != node.id { previousSelectionID = currentSpace.selectedNodeID }
        currentSpace.selectedNodeID = node.id
        node.lastActiveAt = Date()
        node.allTabs.forEach { tab in
            tab.lastActiveAt = Date()
            loadPage(for: tab)
        }
        focusedPaneID = node.isSplit ? node.children.first?.id : node.id
        isFindBarVisible = false
        store.saveSoon()
    }

    func handOffPictureInPicture(from leavingNode: SidebarNode?, to enteringNode: SidebarNode?) {
        guard store.settings.autoPictureInPicture, leavingNode?.id != enteringNode?.id else { return }
        leavingNode?.allTabs.forEach { AutoPictureInPicture.enter($0.page) }
        enteringNode?.allTabs.forEach { AutoPictureInPicture.exit($0.page) }
    }

    func setPictureInPictureForVisibleTabs(isEntering: Bool) {
        guard store.settings.autoPictureInPicture else { return }
        selectedNode?.allTabs.forEach { isEntering ? AutoPictureInPicture.enter($0.page) : AutoPictureInPicture.exit($0.page) }
    }

    func focusPane(_ paneID: UUID) {
        focusedPaneID = paneID
    }

    @discardableResult
    func loadPage(for node: SidebarNode, configuration: WKWebViewConfiguration? = nil) -> WebPage {
        let page = store.ensurePage(for: node, profileID: profileID, isPrivate: isPrivate, configuration: configuration)
        page.host = self
        return page
    }

    func switchToSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        switchToSpace(spaces[index])
    }

    func switchToSpace(_ space: Space) {
        let leavingNode = selectedNode
        selectedSpaceID = space.id
        handOffPictureInPicture(from: leavingNode, to: selectedNode)
        if !isPrivate { store.lastSpaceID = space.id }
        if let selectedNode { select(selectedNode) }
        store.saveSoon()
    }

    func switchSpace(by offset: Int) {
        let targetIndex = currentSpaceIndex + offset
        guard spaces.indices.contains(targetIndex) else { return }
        switchToSpace(at: targetIndex)
    }

    func openInNewTab(_ url: URL?, inBackground: Bool = false, space: Space? = nil) -> SidebarNode {
        let targetSpace = space ?? currentSpace
        let node = SidebarNode.tab(url: url)
        insertToday(node, in: targetSpace)
        if !inBackground {
            if targetSpace.id != selectedSpaceID { selectedSpaceID = targetSpace.id }
            select(node)
        }
        return node
    }

    func open(_ url: URL, mode: CommandBarMode) {
        switch mode {
        case .newTab:
            _ = openInNewTab(url)
        case .navigateCurrent:
            guard let activeTab else { return _ = openInNewTab(url) }
            if activeTab.url == nil { activeTab.url = url }
            loadPage(for: activeTab).load(url)
        case .navigate(let nodeID):
            guard let node = store.node(nodeID) ?? currentSpace.today.find(nodeID) else { return _ = openInNewTab(url) }
            if node.url == nil { node.url = url }
            loadPage(for: node).load(url)
        }
    }

    func adopt(_ node: SidebarNode) {
        insertToday(node, in: currentSpace)
        select(node)
    }

    func reveal(_ node: SidebarNode) {
        let owningSpace = spaces.first { $0.allNodes.find(node.id) != nil }
        if let owningSpace, owningSpace.id != selectedSpaceID { switchToSpace(owningSpace) }
        select(node)
    }

    func closeCurrent() {
        if peek != nil { return closePeek() }
        guard let selectedNode else { return }
        if selectedNode.isSplit { return closeFocusedPane() }
        close(selectedNode)
    }

    func startConversation(_ text: String, browsing: Bool, in nodeID: UUID?) {
        let node = nodeID.flatMap { store.node($0) ?? currentSpace.today.find($0) } ?? openInNewTab(nil)
        let conversation = pageConversations[node.id] ?? AssistantModel(windowModel: self)
        conversation.homeNodeID = node.id
        conversation.contextScope = .none
        pageConversations[node.id] = conversation
        node.conversationID = conversation.id
        if node.title.isEmpty { node.title = String(text.prefix(LayoutConstants.conversationTitleLength)) }
        select(node)
        browsing ? conversation.browse(text) : conversation.send(text)
    }

    func openConversation(_ conversationID: UUID) {
        isHistoryPresented = false
        if let existing = currentSpace.allNodes.allTabs.first(where: { $0.conversationID == conversationID }) {
            return select(existing)
        }
        guard let stored = ConversationStore.shared.conversation(conversationID) else { return }
        let node = SidebarNode.tab(url: nil, title: String(stored.title.prefix(LayoutConstants.conversationTitleLength)))
        node.conversationID = conversationID
        insertToday(node, in: currentSpace)
        select(node)
    }

    func restoreConversation(for node: SidebarNode) {
        guard pageConversations[node.id] == nil, let conversationID = node.conversationID,
              let stored = ConversationStore.shared.conversation(conversationID) else { return }
        let conversation = AssistantModel(windowModel: self, restoring: stored)
        conversation.homeNodeID = node.id
        conversation.contextScope = .none
        pageConversations[node.id] = conversation
    }

    func close(_ node: SidebarNode) {
        pageConversations[node.id]?.stop()
        pageConversations[node.id] = nil
        let isSelected = currentSpace.selectedNodeID == node.id
        let fallback = isSelected ? neighborTodayNode(of: node) : nil
        if isTodayNode(node) {
            removeToday(node)
        } else {
            store.unloadPages(in: node)
        }
        guard isSelected else { return }
        currentSpace.selectedNodeID = nil
        if let fallback { select(fallback) }
    }

    func finishRenaming(_ node: SidebarNode, with newName: String?) {
        guard renamingNodeID == node.id else { return }
        renamingNodeID = nil
        guard let newName else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if node.isFolder {
            if !trimmedName.isEmpty { node.title = trimmedName }
        } else {
            node.customTitle = trimmedName.isEmpty ? nil : trimmedName
        }
        store.saveSoon()
    }

    func reopenClosedTab() {
        guard !isPrivate, let closed = store.recentlyClosed.popLast() else { return }
        _ = openInNewTab(closed.url, space: store.space(id: closed.spaceID))
    }

    func togglePin() {
        guard !isPrivate, let selectedNode, !isSelectedNodeFavorite else { return }
        let destination: NodeContainer = isTodayNode(selectedNode) ? .pinned(spaceID: currentSpace.id) : .today(spaceID: currentSpace.id)
        let index = isTodayNode(selectedNode) ? nil : 0
        store.move(selectedNode.id, into: destination, at: index)
        selectedNode.page?.isAutoPeekSource = store.isPinnedOrFavorite(selectedNode.id)
    }

    func addToFavorites(_ node: SidebarNode) {
        guard !isPrivate else { return }
        store.move(node.id, into: .favorites(profileID: currentSpace.profileID))
        node.page?.isAutoPeekSource = true
    }

    func createFolder(in container: NodeContainer) {
        guard !isPrivate else { return }
        store.insert(.folder(title: "Nueva carpeta"), into: container, at: 0)
    }

    func duplicateFolder(_ folder: SidebarNode) {
        guard let container = store.container(of: folder.id), let index = store.index(of: folder.id, in: container) else { return }
        let copy = folder.duplicated()
        copy.title = folder.title.isEmpty ? "Copia" : folder.title + " (copia)"
        store.insert(copy, into: container, at: index + 1)
    }

    func turnFolderIntoSpace(_ folder: SidebarNode) {
        guard !isPrivate, let detached = store.detach(folder.id) else { return }
        let space = store.addSpace(title: detached.title.isEmpty ? "Nuevo Space" : detached.title, profileID: currentSpace.profileID, theme: currentSpace.theme)
        space.pinned = detached.children
        switchToSpace(space)
        store.saveSoon()
    }

    func selectAdjacentTab(offset: Int) {
        let orderedNodes = (favorites + currentSpace.pinned.flatMap(flattenExpanded) + currentSpace.today).filter { !$0.isFolder }
        guard !orderedNodes.isEmpty else { return }
        let currentIndex = orderedNodes.firstIndex { $0.id == currentSpace.selectedNodeID } ?? -offset
        let targetIndex = (currentIndex + offset + orderedNodes.count) % orderedNodes.count
        select(orderedNodes[targetIndex])
    }

    func isTodayNode(_ node: SidebarNode) -> Bool {
        currentSpace.today.find(node.id) != nil
    }

    private func flattenExpanded(_ node: SidebarNode) -> [SidebarNode] {
        guard node.isFolder else { return [node] }
        return node.isExpanded ? node.children.flatMap(flattenExpanded) : []
    }

    private func neighborTodayNode(of node: SidebarNode) -> SidebarNode? {
        let today = currentSpace.today
        guard let index = today.firstIndex(where: { $0.id == node.id }) else { return today.first }
        let remaining = today.filter { $0.id != node.id }
        return remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
    }

    private func insertToday(_ node: SidebarNode, in space: Space) {
        guard !isPrivate else { return space.today.insert(node, at: 0) }
        store.insert(node, into: .today(spaceID: space.id), at: 0)
    }

    private func removeToday(_ node: SidebarNode) {
        guard !isPrivate else {
            node.allTabs.forEach(store.unloadPage)
            currentSpace.today.removeAll { $0.id == node.id }
            return
        }
        store.remove(node.id)
    }
}

extension WindowModel {
    func splitView() {
        guard !isPrivate, let selectedNode else { return }
        if selectedNode.isSplit { return addBlankPane(to: selectedNode) }
        guard !isSelectedNodeFavorite else { return showToast("Los favoritos no se pueden dividir") }
        let partner = previousSelectionID.flatMap { currentSpace.today.find($0) }.flatMap { $0.isTab && $0.id != selectedNode.id ? $0 : nil }
        createSplit(primary: selectedNode, partner: partner)
    }

    func addToSplit(_ droppedNodeID: UUID) {
        guard !isPrivate, let selectedNode, droppedNodeID != selectedNode.id, let dropped = store.node(droppedNodeID), dropped.isTab else { return }
        guard selectedNode.isSplit else { return createSplit(primary: selectedNode, partner: dropped) }
        guard selectedNode.children.count < LifecycleConstants.maxSplitPanes else { return showToast("Máximo 4 paneles") }
        store.move(droppedNodeID, into: .split(nodeID: selectedNode.id))
        select(selectedNode)
        focusedPaneID = droppedNodeID
    }

    func closeFocusedPane() {
        guard let selectedNode, selectedNode.isSplit, let focusedPaneID else { return }
        let remaining = selectedNode.children.filter { $0.id != focusedPaneID }
        store.remove(focusedPaneID)
        guard let nextSelection = remaining.count == 1 ? remaining.first : selectedNode else { return }
        select(nextSelection)
    }

    private func createSplit(primary: SidebarNode, partner: SidebarNode?) {
        guard let container = store.container(of: primary.id), let index = store.index(of: primary.id, in: container) else { return }
        let secondPane = partner ?? SidebarNode.tab(url: nil)
        let partnerIndex = partner.flatMap { store.index(of: $0.id, in: container) }
        let insertionIndex = partnerIndex.map { $0 < index ? index - 1 : index } ?? index
        store.detach(primary.id)
        if let partner { store.detach(partner.id) }
        let split = SidebarNode.split(panes: [primary, secondPane])
        store.insert(split, into: container, at: insertionIndex)
        select(split)
        guard partner == nil else { return }
        focusedPaneID = secondPane.id
        presentCommandBar(mode: .navigate(nodeID: secondPane.id))
    }

    private func addBlankPane(to split: SidebarNode) {
        guard split.children.count < LifecycleConstants.maxSplitPanes else { return showToast("Máximo 4 paneles") }
        let pane = SidebarNode.tab(url: nil)
        store.insert(pane, into: .split(nodeID: split.id))
        select(split)
        focusedPaneID = pane.id
        presentCommandBar(mode: .navigate(nodeID: pane.id))
    }
}

extension WindowModel {
    func presentCommandBar(mode: CommandBarMode) {
        let initialText = mode == .navigateCurrent ? activePage?.currentURL?.absoluteString ?? "" : ""
        window?.makeFirstResponder(nil)
        commandBar = CommandBarModel(windowModel: self, mode: mode, initialText: initialText)
    }

    func dismissCommandBar() {
        commandBar = nil
    }

    func dismissTransientUI() -> Bool {
        if linkPreview != nil {
            dismissLinkPreview()
            return true
        }
        if isHistoryPresented {
            isHistoryPresented = false
            return true
        }
        if commandBar != nil {
            commandBar = nil
            return true
        }
        if peek != nil {
            closePeek()
            return true
        }
        if isFindBarVisible {
            isFindBarVisible = false
            return true
        }
        return false
    }

    func closePeek() {
        guard let peek else { return }
        store.unloadPage(peek.node)
        self.peek = nil
    }

    func promotePeek() {
        guard let peek else { return }
        let node = peek.node
        node.url = node.page?.currentURL ?? node.url
        self.peek = nil
        insertToday(node, in: currentSpace)
        select(node)
    }

    func copyCurrentURL() {
        guard let url = activePage?.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("URL copiada")
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: LifecycleConstants.toastDuration)
            if toast == message { toast = nil }
        }
    }

    func reload() { activePage?.webView.reload() }
    func goBack() { activePage?.webView.goBack() }
    func goForward() { activePage?.webView.goForward() }

    func zoom(by delta: Double) {
        guard let webView = activePage?.webView else { return }
        webView.pageZoom = min(max(webView.pageZoom + delta, Self.minimumZoom), Self.maximumZoom)
    }

    func zoomIn() { zoom(by: Self.zoomStep) }
    func zoomOut() { zoom(by: -Self.zoomStep) }
    func resetZoom() { activePage?.webView.pageZoom = 1 }

    func find(_ query: String, backwards: Bool = false) {
        guard let webView = activePage?.webView, !query.isEmpty else { return findHasNoMatch = false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            self?.findHasNoMatch = !result.matchFound
        }
    }

    func handlePointer(at location: NSPoint, windowWidth: CGFloat) {
        let revealDistance = LayoutConstants.hoverEdgeWidth
        let dismissMargin: CGFloat = 40
        let isOverlayOpen = commandBar != nil || isNewSpacePresented || isThemeEditorPresented
        if !isSidebarPinned {
            let usesSidebar = store.settings.layout == .sidebar
            let pointerDistance = usesSidebar ? location.x : (window?.contentView?.bounds.height ?? 0) - location.y
            let chromeExtent = usesSidebar ? sidebarWidth + SidebarViewMetrics.outerInset : LayoutConstants.topBarHeight
            if pointerDistance <= revealDistance { scheduleReveal(.sidebar) } else { cancelReveal(.sidebar) }
            if isSidebarHovering, pointerDistance > chromeExtent + dismissMargin, !isOverlayOpen { isSidebarHovering = false }
        }
        guard !isAssistantPresented else { return }
        let distanceFromRight = windowWidth - location.x
        if distanceFromRight <= revealDistance, !isShowingStartPage { scheduleReveal(.assistant) } else { cancelReveal(.assistant) }
        let assistantEdge = AssistantPanelMetrics.width + SidebarViewMetrics.outerInset * 2 + dismissMargin
        if isAssistantHovering, distanceFromRight > assistantEdge, !isOverlayOpen { isAssistantHovering = false }
    }

    func scheduleReveal(_ edge: RevealEdge) {
        guard pendingReveals[edge] == nil, !isRevealed(edge) else { return }
        let delay = store.settings.edgeRevealDelayMilliseconds
        guard delay > 0 else { return reveal(edge) }
        pendingReveals[edge] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self?.reveal(edge)
        }
    }

    func cancelReveal(_ edge: RevealEdge) {
        pendingReveals[edge]?.cancel()
        pendingReveals[edge] = nil
    }

    func updateReveal(_ edge: RevealEdge, isPointerInside: Bool) {
        if isPointerInside { scheduleReveal(edge) } else { cancelReveal(edge) }
    }

    private func isRevealed(_ edge: RevealEdge) -> Bool {
        switch edge {
        case .sidebar: isSidebarHovering
        case .assistant: isAssistantHovering
        }
    }

    private func reveal(_ edge: RevealEdge) {
        pendingReveals[edge] = nil
        switch edge {
        case .sidebar: isSidebarHovering = true
        case .assistant: isAssistantHovering = true
        }
    }

    var assistant: AssistantModel {
        agents.first { $0.id == activeAgentID } ?? agents[0]
    }

    func newAgent() {
        let agent = AssistantModel(windowModel: self)
        agents.append(agent)
        selectAgent(agent.id)
    }

    func selectAgent(_ agentID: UUID) {
        activeAgentID = agentID
        agents.first { $0.id == agentID }?.hasUnseenResult = false
    }

    func closeAgent(_ agentID: UUID) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        agents[index].stop()
        agents.remove(at: index)
        if agents.isEmpty { return newAgent() }
        guard activeAgentID == agentID else { return }
        activeAgentID = agents[max(index - 1, 0)].id
    }

    func finishWelcome() {
        isWelcomePresented = false
        store.settings.hasSeenWelcome = true
        store.saveSoon()
    }

    func toggleSidebarPinned() {
        store.settings.isSidebarPinned.toggle()
        isSidebarHovering = false
        store.saveSoon()
    }
}

extension WindowModel {
    func fillPassword() {
        guard let page = activePage, !page.currentHost.isEmpty else { return }
        let credentials = PasswordVault.shared.credentials(forHost: page.currentHost)
        guard !credentials.isEmpty else { return showToast("No hay contraseñas guardadas para \(page.currentHost)") }
        guard credentials.count == 1, let credential = credentials.first else { return credentialChoices = credentials }
        fill(credential)
    }

    func fill(_ credential: SavedCredential) {
        credentialChoices = []
        guard let page = activePage, page.currentHost == credential.host else { return }
        Task {
            do {
                try await page.fill(credential)
            } catch PasswordVaultError.authenticationFailed {
                showToast("Autenticación cancelada")
            } catch {
                showToast("No se pudo rellenar la contraseña")
            }
        }
    }

    func resolvePasswordOffer(save: Bool, never: Bool = false) {
        guard let offer = passwordOffer else { return }
        passwordOffer = nil
        if never {
            store.settings.passwordNeverHosts.insert(offer.host)
            store.saveSoon()
            return
        }
        guard save else { return }
        do {
            try PasswordVault.shared.save(host: offer.host, account: offer.username, password: offer.password)
            showToast("Contraseña guardada")
        } catch {
            showToast("No se pudo guardar la contraseña")
        }
    }

    func resolvePermission(_ isGranted: Bool) {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        if !isPrivate { store.setPermission(isGranted, profileID: request.profileID, host: request.host, kind: request.kind) }
        request.continuation.resume(returning: isGranted)
    }
}

extension WindowModel {
    func openNewTab(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?, inBackground: Bool) -> WKWebView? {
        let sourceSpace = spaces.first { space in page.node.map { space.allNodes.find($0.id) != nil } ?? false } ?? currentSpace
        let node = SidebarNode.tab(url: url)
        insertToday(node, in: sourceSpace)
        let newPage = loadPage(for: node, configuration: configuration)
        if configuration == nil, let url { newPage.load(url) }
        if !inBackground { reveal(node) }
        return newPage.webView
    }

    func openMiniWindow(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?) -> WKWebView? {
        AppDelegate.shared.openLittleWindow(for: url, profileID: page.profileID, configuration: configuration).model.page.webView
    }

    func openPeek(from page: WebPage, url: URL) {
        closePeek()
        let node = SidebarNode.tab(url: url)
        _ = loadPage(for: node)
        peek = PeekState(node: node)
    }

    func closePage(_ page: WebPage) {
        guard let node = page.node else { return }
        if peek?.node.id == node.id { return closePeek() }
        close(node)
    }

    func requestPermission(host: String, kind: PermissionKind, page: WebPage) async -> Bool {
        if !isPrivate, let decision = store.permissionDecision(profileID: page.profileID, host: host, kind: kind) { return decision }
        guard permissionRequest == nil else { return false }
        return await withCheckedContinuation { continuation in
            permissionRequest = PermissionRequest(host: host, kind: kind, profileID: page.profileID, continuation: continuation)
        }
    }

    func offerPasswordSave(host: String, username: String, password: String) {
        guard !store.settings.passwordNeverHosts.contains(host),
              !PasswordVault.shared.hasPassword(host: host, account: username, password: password) else { return }
        passwordOffer = PasswordOffer(host: host, username: username, password: password)
    }

    func presentingWindow() -> NSWindow? {
        window
    }
}

extension WindowModel {
    func linkPreviewDidChange(_ event: LinkPreviewEvent, from page: WebPage) {
        guard store.settings.showsLinkPreviews, selectedNode?.allTabs.contains(where: { $0.page === page }) == true else { return }
        switch event {
        case .enter(let request): scheduleLinkPreview(request, from: page)
        case .leave: scheduleLinkPreviewDismissal()
        case .dismiss: dismissLinkPreview()
        }
    }

    func dismissLinkPreview() {
        linkPreviewShowTask?.cancel()
        linkPreviewDismissTask?.cancel()
        linkPreview?.tearDown()
        linkPreview = nil
    }

    private func scheduleLinkPreview(_ request: LinkPreviewRequest, from page: WebPage) {
        linkPreviewShowTask?.cancel()
        linkPreviewDismissTask?.cancel()
        guard linkPreview?.url != request.url else { return }
        let anchorFrame = windowFrame(of: request.anchorRect, in: page.webView)
        let delay = Duration.milliseconds(store.settings.linkPreviewDelayMilliseconds)
        linkPreviewShowTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.showLinkPreview(url: request.url, anchorFrame: anchorFrame)
        }
    }

    private func scheduleLinkPreviewDismissal() {
        linkPreviewShowTask?.cancel()
        linkPreviewDismissTask?.cancel()
        guard linkPreview != nil else { return }
        linkPreviewDismissTask = Task { [weak self] in
            try? await Task.sleep(for: LifecycleConstants.linkPreviewDismissGrace)
            guard !Task.isCancelled else { return }
            self?.dismissLinkPreview()
        }
    }

    private func showLinkPreview(url: URL, anchorFrame: CGRect) {
        linkPreview?.tearDown()
        linkPreview = LinkPreviewState(url: url, anchorFrame: anchorFrame, cardSize: store.settings.linkPreviewSize.cardSize)
    }

    private func windowFrame(of rect: CGRect, in webView: WKWebView) -> CGRect {
        let windowRect = webView.convert(rect, to: nil)
        let contentHeight = window?.contentView?.bounds.height ?? 0
        return CGRect(x: windowRect.minX, y: contentHeight - windowRect.maxY, width: windowRect.width, height: windowRect.height)
    }
}
