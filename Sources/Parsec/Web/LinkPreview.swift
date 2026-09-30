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
@Observable
final class LinkPreviewState: Identifiable {
    let id = UUID()
    let url: URL
    let anchorFrame: CGRect
    let page: WebPage

    init(url: URL, anchorFrame: CGRect, cardWidth: CGFloat) {
        self.url = url
        self.anchorFrame = anchorFrame
        let configuration = WebConfigurationFactory.makeIsolatedConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        page = WebPage(profileID: UUID(), isPrivate: true, configuration: configuration)
        page.webView.pageZoom = cardWidth / LinkPreviewMetrics.viewportWidth
        page.load(url)
    }

    func tearDown() {
        page.tearDown()
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
