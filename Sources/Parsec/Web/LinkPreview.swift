import AppKit
import Observation
import WebKit

enum LinkPreviewSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small: "Pequeño"
        case .medium: "Mediano"
        case .large: "Grande"
        }
    }

    var cardSize: CGSize {
        switch self {
        case .small: CGSize(width: 320, height: 240)
        case .medium: CGSize(width: 440, height: 320)
        case .large: CGSize(width: 600, height: 440)
        }
    }
}

enum LinkPreviewMetrics {
    static let viewportWidth: CGFloat = 1100
    static let headerHeight: CGFloat = 44
    static let anchorGap: CGFloat = 10
    static let screenMargin: CGFloat = 12
    static let cornerRadius: CGFloat = 16
}

struct LinkPreviewRequest {
    let url: URL
    let anchorRect: CGRect
}

@MainActor
final class LinkPreviewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var hasCommitted = false

    func load(_ url: URL, in webView: WKWebView, timeout: Duration) async -> Bool {
        let isProtectionReady = await ContentBlocker.shared.waitUntilPrepared()
        guard isProtectionReady, !Task.isCancelled else { return false }
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            finish(hasCommitted)
        }
        let didLoad = await withCheckedContinuation { continuation = $0 }
        timeoutTask.cancel()
        return didLoad
    }

    func cancel() {
        finish(false)
    }

    private func finish(_ didLoad: Bool) {
        continuation?.resume(returning: didLoad)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommitted = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }
}

@MainActor
@Observable
final class LinkPreviewState: Identifiable {
    enum Phase {
        case loading
        case ready(NSImage)
        case failed
    }

    private static let loadTimeout = Duration.seconds(8)
    private static let renderSettleDelay = Duration.milliseconds(250)
    private static let hideScrollbarsSource = "const style = document.createElement('style'); style.textContent = 'html{overflow:hidden!important}::-webkit-scrollbar{display:none!important}'; document.documentElement.appendChild(style);"

    let id = UUID()
    let url: URL
    let anchorFrame: CGRect
    private(set) var phase = Phase.loading
    private(set) var title = ""
    @ObservationIgnored private let loader = LinkPreviewLoader()
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    var isVisible: Bool {
        if case .loading = phase { return false }
        return true
    }

    init(url: URL, anchorFrame: CGRect, cardSize: CGSize) {
        self.url = url
        self.anchorFrame = anchorFrame
        let viewportHeight = LinkPreviewMetrics.viewportWidth * cardSize.height / cardSize.width
        let configuration = WebConfigurationFactory.makeIsolatedConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let scrollbarScript = WKUserScript(source: Self.hideScrollbarsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(scrollbarScript)
        let previewView = WKWebView(frame: CGRect(x: 0, y: 0, width: LinkPreviewMetrics.viewportWidth, height: viewportHeight), configuration: configuration)
        webView = previewView
        loadTask = Task { [weak self] in await self?.capture(previewView, cardWidth: cardSize.width) }
    }

    func tearDown() {
        loadTask?.cancel()
        loader.cancel()
        release()
    }

    private func capture(_ previewView: WKWebView, cardWidth: CGFloat) async {
        let didLoad = await loader.load(url, in: previewView, timeout: Self.loadTimeout)
        guard didLoad, !Task.isCancelled else { return failIfActive() }
        try? await Task.sleep(for: Self.renderSettleDelay)
        guard !Task.isCancelled else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: cardWidth)
        title = previewView.title ?? ""
        let image = try? await previewView.takeSnapshot(configuration: configuration)
        guard !Task.isCancelled else { return }
        phase = image.map(Phase.ready) ?? .failed
        release()
    }

    private func failIfActive() {
        guard !Task.isCancelled else { return }
        phase = .failed
        release()
    }

    private func release() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

@MainActor
final class LinkPreviewMessageRouter: NSObject, WKScriptMessageHandler {
    static let shared = LinkPreviewMessageRouter()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let webView = message.webView, let page = WebPage.page(for: webView) else { return }
        page.handleLinkPreviewMessage(message.body)
    }
}

@MainActor
extension WebPage {
    private enum LinkPreviewMessageType: String {
        case enter
        case leave
        case dismiss
    }

    private static let hrefKey = "href"
    private static let messageTypeKey = "type"
    private static let rectKeys = ["x", "y", "width", "height"]

    func handleLinkPreviewMessage(_ body: Any) {
        guard BrowserStore.shared.settings.showsLinkPreviews,
              let payload = body as? [String: Any],
              let rawType = payload[Self.messageTypeKey] as? String,
              let messageType = LinkPreviewMessageType(rawValue: rawType) else { return }
        switch messageType {
        case .leave: host?.linkPreviewDidChange(.leave, from: self)
        case .dismiss: host?.linkPreviewDidChange(.dismiss, from: self)
        case .enter:
            guard let request = linkPreviewRequest(from: payload) else { return }
            host?.linkPreviewDidChange(.enter(request), from: self)
        }
    }

    private func linkPreviewRequest(from payload: [String: Any]) -> LinkPreviewRequest? {
        guard let href = payload[Self.hrefKey] as? String, let url = URL(string: href) else { return nil }
        let values = Self.rectKeys.compactMap { (payload[$0] as? NSNumber)?.doubleValue }
        guard values.count == Self.rectKeys.count else { return nil }
        let zoom = webView.pageZoom
        let rect = CGRect(x: values[0] * zoom, y: values[1] * zoom, width: values[2] * zoom, height: values[3] * zoom)
        return LinkPreviewRequest(url: url, anchorRect: rect)
    }
}

enum LinkPreviewEvent {
    case enter(LinkPreviewRequest)
    case leave
    case dismiss
}
