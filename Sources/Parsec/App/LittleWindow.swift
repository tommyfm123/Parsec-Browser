import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class LittleWindowModel: WebPageHost {
    let node: SidebarNode
    let page: WebPage
    @ObservationIgnored weak var window: NSWindow?

    init(url: URL?, profileID: UUID, configuration: WKWebViewConfiguration? = nil) {
        node = SidebarNode.tab(url: url)
        page = BrowserStore.shared.ensurePage(for: node, profileID: profileID, isPrivate: false, configuration: configuration)
        page.host = self
    }

    func promote() {
        let promotedNode = node
        promotedNode.url = page.currentURL ?? promotedNode.url
        window?.close()
        AppDelegate.shared.adoptIntoMainWindow(promotedNode)
    }

    func discard() {
        BrowserStore.shared.unloadPage(node)
    }

    func openNewTab(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?, inBackground: Bool) -> WKWebView? {
        AppDelegate.shared.showMainWindow()
        return AppDelegate.shared.mainModel?.openNewTab(from: page, url: url, configuration: configuration, inBackground: inBackground)
    }

    func openMiniWindow(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?) -> WKWebView? {
        openNewTab(from: page, url: url, configuration: configuration, inBackground: false)
    }

    func openPeek(from page: WebPage, url: URL) {
        page.load(url)
    }

    func closePage(_ page: WebPage) {
        window?.close()
    }

    func requestPermission(host: String, kind: PermissionKind, page: WebPage) async -> Bool {
        if let decision = BrowserStore.shared.permissionDecision(profileID: page.profileID, host: host, kind: kind) { return decision }
        let alert = NSAlert()
        alert.messageText = "\(host) quiere usar \(kind.label)"
        alert.addButton(withTitle: "Permitir")
        alert.addButton(withTitle: "Bloquear")
        let isGranted = alert.runModal() == .alertFirstButtonReturn
        BrowserStore.shared.setPermission(isGranted, profileID: page.profileID, host: host, kind: kind)
        return isGranted
    }

    func offerPasswordSave(host: String, username: String, password: String) {}

    func presentingWindow() -> NSWindow? {
        window
    }
}

@MainActor
final class LittleWindow: NSWindow, NSWindowDelegate {
    override func noResponder(for eventSelector: Selector) {
        guard eventSelector == #selector(NSResponder.keyDown(with:)), firstResponder?.isInsideWebView == true else {
            return super.noResponder(for: eventSelector)
        }
    }

    let model: LittleWindowModel
    var onClose: (() -> Void)?
    private var isPromoting = false

    init(model: LittleWindowModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: LayoutConstants.littleWindowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        minSize = LittleWindowMetrics.minimumSize
        isReleasedWhenClosed = false
        level = .floating
        tabbingMode = .disallowed
        delegate = self
        contentView = NSHostingView(rootView: LittleBrowserView(model: model))
        model.window = self
        center()
        layoutTrafficLights()
    }

    func layoutTrafficLights() {
        positionTrafficLights(centerY: LittleWindowMetrics.toolbarHeight / 2, leadingInset: LittleWindowMetrics.trafficLightsLeadingInset)
    }

    func windowDidResize(_ notification: Notification) {
        layoutTrafficLights()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        layoutTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        if !isPromoting { model.discard() }
        onClose?()
    }

    @objc func promoteToTabAction(_ sender: Any?) {
        isPromoting = true
        model.promote()
    }

    @objc func closeTabAction(_ sender: Any?) { close() }
    @objc func dismissOverlayAction(_ sender: Any?) { close() }
    @objc func reloadAction(_ sender: Any?) { model.page.webView.reload() }
    @objc func goBackAction(_ sender: Any?) { model.page.webView.goBack() }
    @objc func goForwardAction(_ sender: Any?) { model.page.webView.goForward() }

    @objc func copyURLAction(_ sender: Any?) {
        guard let url = model.page.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
