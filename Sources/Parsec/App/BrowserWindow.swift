import AppKit
import SwiftUI

@MainActor
final class BrowserWindow: NSWindow, NSWindowDelegate {
    private static let frameAutosaveName = "ParsecMainWindow"
    private static let privateTitle = "Parsec — Privado"

    private static let trafficLightsLeadingInset: CGFloat = 20
    private static let trafficLightButtonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    let model: WindowModel
    var onClose: (() -> Void)?
    var trafficLightsCenterY: CGFloat = 0 {
        didSet { layoutTrafficLights() }
    }
    private var findQuery = ""

    init(model: WindowModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: LayoutConstants.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        title = model.isPrivate ? Self.privateTitle : "Parsec"
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        delegate = self
        tabbingMode = .disallowed
        minSize = NSSize(width: 640, height: 420)
        contentView = NSHostingView(rootView: BrowserRootView(model: model))
        acceptsMouseMovedEvents = true
        model.window = self
        center()
        if !model.isPrivate { setFrameAutosaveName(Self.frameAutosaveName) }
        setTrafficLightsVisible(model.isChromeVisible)
    }

    func setTrafficLightsVisible(_ isVisible: Bool) {
        Self.trafficLightButtonTypes.forEach { buttonType in
            standardWindowButton(buttonType)?.isHidden = !isVisible
        }
        layoutTrafficLights()
    }

    func layoutTrafficLights() {
        let buttons = Self.trafficLightButtonTypes.compactMap(standardWindowButton)
        guard trafficLightsCenterY > 0, !styleMask.contains(.fullScreen), let firstButton = buttons.first,
              let titlebarContainer = firstButton.superview?.superview else { return }
        let buttonHeight = firstButton.frame.height
        let containerHeight = trafficLightsCenterY + buttonHeight / 2 + 4
        titlebarContainer.frame = NSRect(x: titlebarContainer.frame.minX, y: frame.height - containerHeight, width: titlebarContainer.frame.width, height: containerHeight)
        firstButton.superview?.frame = titlebarContainer.bounds
        let spacing = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
        let originY = containerHeight - trafficLightsCenterY - buttonHeight / 2
        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(NSPoint(x: Self.trafficLightsLeadingInset + CGFloat(index) * spacing, y: originY))
        }
    }

    func windowDidResize(_ notification: Notification) {
        layoutTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        layoutTrafficLights()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        model.setPictureInPictureForVisibleTabs(isEntering: true)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        model.setPictureInPictureForVisibleTabs(isEntering: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        layoutTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        model.closePeek()
        if model.isPrivate { model.currentSpace.today.forEach(BrowserStore.shared.unloadPages) }
        onClose?()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: focusPane(at: event.locationInWindow)
        case .mouseMoved, .leftMouseDragged: model.handlePointer(at: event.locationInWindow, windowWidth: frame.width)
        default: break
        }
        super.sendEvent(event)
    }

    private func focusPane(at location: NSPoint) {
        guard let split = model.selectedNode, split.isSplit else { return }
        let clickedPane = split.children.first { pane in
            guard let webView = pane.page?.webView, webView.window === self else { return false }
            return webView.bounds.contains(webView.convert(location, from: nil))
        }
        if let clickedPane { model.focusPane(clickedPane.id) }
    }

    func updateFindQuery(_ query: String) {
        findQuery = query
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(dismissOverlayAction(_:)):
            model.commandBar != nil || model.peek != nil || model.isFindBarVisible
        case #selector(promoteToTabAction(_:)):
            model.peek != nil
        case #selector(closePaneAction(_:)):
            model.selectedNode?.isSplit == true
        case #selector(togglePinAction(_:)), #selector(splitViewAction(_:)), #selector(newSpaceAction(_:)), #selector(editThemeAction(_:)), #selector(toggleAssistantAction(_:)):
            !model.isPrivate
        default:
            super.validateMenuItem(menuItem)
        }
    }

    @objc func newTabAction(_ sender: Any?) { model.presentCommandBar(mode: .newTab) }
    @objc func editURLAction(_ sender: Any?) { model.presentCommandBar(mode: .navigateCurrent) }
    @objc func promoteToTabAction(_ sender: Any?) { model.promotePeek() }
    @objc func closeTabAction(_ sender: Any?) { model.closeCurrent() }
    @objc func reopenTabAction(_ sender: Any?) { model.reopenClosedTab() }
    @objc func copyURLAction(_ sender: Any?) { model.copyCurrentURL() }
    @objc func findAction(_ sender: Any?) { model.isFindBarVisible = true }
    @objc func findNextAction(_ sender: Any?) { model.find(findQuery) }
    @objc func findPreviousAction(_ sender: Any?) { model.find(findQuery, backwards: true) }
    @objc func fillPasswordAction(_ sender: Any?) { model.fillPassword() }
    @objc func toggleSidebarAction(_ sender: Any?) { model.toggleSidebarPinned() }
    @objc func toggleLayoutAction(_ sender: Any?) { CommandRouter.toggleLayout() }
    @objc func reloadAction(_ sender: Any?) { model.reload() }
    @objc func reloadFromOriginAction(_ sender: Any?) { model.activePage?.webView.reloadFromOrigin() }
    @objc func viewSourceAction(_ sender: Any?) { DeveloperTools.showSource(in: model) }
    @objc func copyUserAgentAction(_ sender: Any?) { DeveloperTools.copyUserAgent(in: model) }
    @objc func goBackAction(_ sender: Any?) { model.goBack() }
    @objc func goForwardAction(_ sender: Any?) { model.goForward() }
    @objc func zoomInAction(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOutAction(_ sender: Any?) { model.zoomOut() }
    @objc func actualSizeAction(_ sender: Any?) { model.resetZoom() }
    @objc func dismissOverlayAction(_ sender: Any?) { _ = model.dismissTransientUI() }
    @objc func togglePinAction(_ sender: Any?) { model.togglePin() }
    @objc func splitViewAction(_ sender: Any?) { model.splitView() }
    @objc func closePaneAction(_ sender: Any?) { model.closeFocusedPane() }
    @objc func nextTabAction(_ sender: Any?) { model.selectAdjacentTab(offset: 1) }
    @objc func previousTabAction(_ sender: Any?) { model.selectAdjacentTab(offset: -1) }
    @objc func newSpaceAction(_ sender: Any?) { model.isNewSpacePresented = true }
    @objc func editThemeAction(_ sender: Any?) { model.isThemeEditorPresented = true }
    @objc func nextSpaceAction(_ sender: Any?) { model.switchSpace(by: 1) }
    @objc func previousSpaceAction(_ sender: Any?) { model.switchSpace(by: -1) }
    @objc func toggleAssistantAction(_ sender: Any?) { model.isAssistantPresented.toggle() }
    @objc func toggleHistoryAction(_ sender: Any?) { model.isHistoryPresented = !model.isHistoryPresented && !model.isPrivate }
    @objc func selectSpaceAction(_ sender: NSMenuItem) { model.switchToSpace(at: sender.tag) }
}
