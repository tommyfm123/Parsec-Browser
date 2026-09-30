import AppKit
import Observation
import WebKit

enum PermissionKind: String {
    case camera
    case microphone
    case cameraAndMicrophone

    init(_ captureType: WKMediaCaptureType) {
        switch captureType {
        case .camera: self = .camera
        case .microphone: self = .microphone
        default: self = .cameraAndMicrophone
        }
    }

    var label: String {
        switch self {
        case .camera: "la cámara"
        case .microphone: "el micrófono"
        case .cameraAndMicrophone: "la cámara y el micrófono"
        }
    }
}

@MainActor
protocol WebPageHost: AnyObject {
    func openNewTab(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?, inBackground: Bool) -> WKWebView?
    func openMiniWindow(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?) -> WKWebView?
    func openPeek(from page: WebPage, url: URL)
    func closePage(_ page: WebPage)
    func requestPermission(host: String, kind: PermissionKind, page: WebPage) async -> Bool
    func offerPasswordSave(host: String, username: String, password: String)
    func suggestPasswordFill(for page: WebPage)
    func presentingWindow() -> NSWindow?
    func linkPreviewDidChange(_ event: LinkPreviewEvent, from page: WebPage)
}

extension WebPageHost {
    func linkPreviewDidChange(_ event: LinkPreviewEvent, from page: WebPage) {}
}

extension WebPageHost {
    func suggestPasswordFill(for page: WebPage) {}
}

@MainActor
@Observable
final class WebPage: NSObject {
    private enum AutofillMessageType: String {
        case formDetected
        case submitted
    }

    private static let registry = NSMapTable<WKWebView, WebPage>.weakToWeakObjects()
    private static let messageTypeKey = "type"
    private static let usernameKey = "username"
    private static let passwordKey = "password"
    private static let faviconScript = "return document.querySelector(\"link[rel~='icon']\")?.href ?? null;"
    private static let fillScript = "return window.parsecFillCredentials(username, password);"
    private static let cancelledErrorCodes: Set<Int> = [NSURLErrorCancelled, 102]
    private static let middleMouseButtonNumbers: Set<Int> = [2, 4]

    let webView: WKWebView
    let profileID: UUID
    let isPrivate: Bool

    var title = ""
    var currentURL: URL?
    var progress = 0.0
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var isUsingCamera = false
    var isUsingMicrophone = false
    var hasSavedCredentials = false
    var hasCommittedNavigation = false
    var agentActivity: String?

    @ObservationIgnored weak var node: SidebarNode?
    @ObservationIgnored weak var host: WebPageHost?
    @ObservationIgnored var isAutoPeekSource = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var upgradedURLs: Set<URL> = []
    @ObservationIgnored private var allowedHTTPHosts: Set<String> = []
    @ObservationIgnored private var isBlockerApplied = true

    var isCapturingMedia: Bool { isUsingCamera || isUsingMicrophone }
    var currentHost: String { currentURL?.host() ?? "" }

    static func page(for webView: WKWebView) -> WebPage? {
        registry.object(forKey: webView)
    }

    init(profileID: UUID, isPrivate: Bool, configuration: WKWebViewConfiguration? = nil) {
        self.profileID = profileID
        self.isPrivate = isPrivate
        let resolvedConfiguration = configuration ?? WebConfigurationFactory.makeConfiguration(profileID: profileID, isPrivate: isPrivate)
        webView = WKWebView(frame: .zero, configuration: resolvedConfiguration)
        super.init()
        webView.isInspectable = BrowserStore.shared.settings.developerMode
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        Self.registry.setObject(self, forKey: webView)
        observeWebView()
    }

    func load(_ url: URL) {
        guard url.isFileURL else { return loadRequest(url) }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func applyBlockerRules() {
        ContentBlocker.shared.install(on: webView.configuration.userContentController, includesBlocker: isBlockerApplied)
    }

    func tearDown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
        webView.removeFromSuperview()
        Self.registry.removeObject(forKey: webView)
    }

    func fill(_ credential: SavedCredential) async throws {
        let password = try await PasswordVault.shared.authenticatedPassword(for: credential)
        _ = try await webView.callAsyncJavaScript(
            Self.fillScript,
            arguments: [Self.usernameKey: credential.account, Self.passwordKey: password],
            in: nil,
            contentWorld: WebConfigurationFactory.autofillWorld
        )
    }

    func handleAutofillMessage(_ body: Any, originHost: String) {
        guard let payload = body as? [String: Any],
              let rawType = payload[Self.messageTypeKey] as? String,
              let messageType = AutofillMessageType(rawValue: rawType),
              originHost == currentHost else { return }
        switch messageType {
        case .formDetected:
            hasSavedCredentials = !PasswordVault.shared.credentials(forHost: originHost).isEmpty
            if hasSavedCredentials { host?.suggestPasswordFill(for: self) }
        case .submitted:
            let username = payload[Self.usernameKey] as? String ?? ""
            let password = payload[Self.passwordKey] as? String ?? ""
            guard !isPrivate, !password.isEmpty else { return }
            host?.offerPasswordSave(host: originHost, username: username, password: password)
        }
    }

    private func loadRequest(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.title) { [weak self] webView, _ in Task { @MainActor in self?.title = webView.title ?? "" } },
            webView.observe(\.url) { [weak self] webView, _ in Task { @MainActor in self?.updateURL(webView.url) } },
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in Task { @MainActor in self?.progress = webView.estimatedProgress } },
            webView.observe(\.isLoading) { [weak self] webView, _ in Task { @MainActor in self?.isLoading = webView.isLoading } },
            webView.observe(\.canGoBack) { [weak self] webView, _ in Task { @MainActor in self?.canGoBack = webView.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] webView, _ in Task { @MainActor in self?.canGoForward = webView.canGoForward } },
            webView.observe(\.cameraCaptureState) { [weak self] webView, _ in Task { @MainActor in self?.isUsingCamera = webView.cameraCaptureState == .active } },
            webView.observe(\.microphoneCaptureState) { [weak self] webView, _ in Task { @MainActor in self?.isUsingMicrophone = webView.microphoneCaptureState == .active } },
        ]
    }

    private func updateURL(_ url: URL?) {
        guard let url, url.scheme != WebConstants.httpContinueScheme else { return }
        if url.host() != currentURL?.host() { hasSavedCredentials = false }
        currentURL = url
    }

    private func syncBlocker(for url: URL) {
        let shouldBlock = !BrowserStore.shared.isBlockerDisabled(host: url.host() ?? "")
        guard shouldBlock != isBlockerApplied else { return }
        isBlockerApplied = shouldBlock
        ContentBlocker.shared.install(on: webView.configuration.userContentController, includesBlocker: shouldBlock)
    }

    private func upgradedURL(for url: URL) -> URL? {
        guard url.scheme == WebConstants.httpScheme, let host = url.host() else { return nil }
        guard !InputResolver.isLocalHost(host), !allowedHTTPHosts.contains(host) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = WebConstants.httpsScheme
        return components?.url
    }

    private func continueOverHTTP(_ continueURL: URL) {
        let originalString = continueURL.absoluteString.dropFirst(WebConstants.httpContinueScheme.count + 1)
        guard let originalURL = URL(string: String(originalString)), let host = originalURL.host() else { return }
        allowedHTTPHosts.insert(host)
        loadRequest(originalURL)
    }

    private func shouldPeek(_ action: WKNavigationAction, url: URL) -> Bool {
        guard action.navigationType == .linkActivated else { return false }
        if action.modifierFlags.contains(.shift) { return true }
        guard isAutoPeekSource, let sourceHost = node?.url?.host() else { return false }
        return Self.baseHost(url.host() ?? "") != Self.baseHost(sourceHost)
    }

    private static func baseHost(_ host: String) -> String {
        host.replacingOccurrences(of: WebConstants.wwwPrefix, with: "")
    }

    private func openLinkInNewContext(url: URL?, configuration: WKWebViewConfiguration?, inBackground: Bool) -> WKWebView? {
        guard !isPrivate, BrowserStore.shared.settings.linkOpening == .miniWindow else {
            return host?.openNewTab(from: self, url: url, configuration: configuration, inBackground: inBackground)
        }
        return host?.openMiniWindow(from: self, url: url, configuration: configuration)
    }

    private func recordVisit() {
        guard !isPrivate, let url = currentURL, url.scheme?.hasPrefix(WebConstants.httpScheme) == true else { return }
        BrowserStore.shared.history.recordVisit(profileID: profileID, url: url, title: title)
    }

    private func refreshFavicon() {
        guard let pageHost = currentURL?.host() else { return }
        Task {
            let result = try? await webView.callAsyncJavaScript(Self.faviconScript, arguments: [:], in: nil, contentWorld: .defaultClient)
            guard let href = result as? String, let iconURL = URL(string: href) else { return }
            FaviconStore.shared.updateIcon(host: pageHost, iconURL: iconURL)
        }
    }

    private func showErrorPage(_ html: String, for url: URL) {
        webView.loadHTMLString(html, baseURL: nil)
        currentURL = url
    }
}

extension WebPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let policy = policy(for: navigationAction)
        decisionHandler(policy, preferences)
    }

    private func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { return .download }
        guard let url = action.request.url else { return .allow }
        if url.scheme == WebConstants.httpContinueScheme {
            continueOverHTTP(url)
            return .cancel
        }
        guard action.targetFrame?.isMainFrame == true else { return .allow }
        if let blockedHost = url.host(), BrowserStore.shared.settings.isBlocked(host: blockedHost) {
            showErrorPage(ErrorPages.blockedSite(host: blockedHost), for: url)
            return .cancel
        }
        if let secureURL = upgradedURL(for: url) {
            upgradedURLs.insert(secureURL)
            loadRequest(secureURL)
            return .cancel
        }
        let opensInNewContext = action.modifierFlags.contains(.command) || Self.middleMouseButtonNumbers.contains(action.buttonNumber)
        if action.navigationType == .linkActivated, opensInNewContext {
            _ = openLinkInNewContext(url: url, configuration: nil, inBackground: true)
            return .cancel
        }
        if shouldPeek(action, url: url) {
            host?.openPeek(from: self, url: url)
            return .cancel
        }
        syncBlocker(for: url)
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommittedNavigation = true
        hasSavedCredentials = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recordVisit()
        refreshFavicon()
        BrowserStore.shared.pageDidFinishNavigation(self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard !Self.cancelledErrorCodes.contains(nsError.code) else { return }
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url
        guard let failingURL else { return }
        let isFailedUpgrade = upgradedURLs.contains(failingURL)
        let html = isFailedUpgrade ? ErrorPages.insecureConnection(for: failingURL) : ErrorPages.loadFailure(for: failingURL, message: nsError.localizedDescription)
        showErrorPage(html, for: failingURL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension WebPage: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.navigationType == .linkActivated else {
            return host?.openNewTab(from: self, url: navigationAction.request.url, configuration: configuration, inBackground: false)
        }
        return openLinkInNewContext(url: navigationAction.request.url, configuration: configuration, inBackground: false)
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.closePage(self)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        guard let host else { return decisionHandler(.deny) }
        Task {
            let isGranted = await host.requestPermission(host: origin.host, kind: PermissionKind(type), page: self)
            decisionHandler(isGranted ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = JavaScriptDialog.alert(message: message, host: frame.securityOrigin.host)
        JavaScriptDialog.present(alert, in: host?.presentingWindow()) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = JavaScriptDialog.confirm(message: message, host: frame.securityOrigin.host)
        JavaScriptDialog.present(alert, in: host?.presentingWindow()) { response in completionHandler(response == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let (alert, field) = JavaScriptDialog.prompt(message: prompt, defaultText: defaultText, host: frame.securityOrigin.host)
        JavaScriptDialog.present(alert, in: host?.presentingWindow()) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        guard let window = host?.presentingWindow() else {
            return completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
}
