import AppKit
import Foundation
import WebKit

@MainActor
final class AuditHost: WebPageHost {
    var permissionCount = 0
    var permissionResult = false
    var delaysPermission = false
    func openNewTab(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?, inBackground: Bool) -> WKWebView? { nil }
    func openMiniWindow(from page: WebPage, url: URL?, configuration: WKWebViewConfiguration?) -> WKWebView? { nil }
    func openPeek(from page: WebPage, url: URL) {}
    func closePage(_ page: WebPage) {}
    func requestPermission(host: String, kind: PermissionKind, page: WebPage) async -> Bool {
        permissionCount += 1
        if delaysPermission {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return false }
        }
        return permissionResult
    }
    func offerPasswordSave(host: String, username: String, password: String) {}
    func presentingWindow() -> NSWindow? { nil }
}

@MainActor
final class AuditFrameCapture: NSObject, WKScriptMessageHandler {
    var frames: [String: WKFrameInfo] = [:]
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let key = message.body as? String { frames[key] = message.frameInfo }
    }
}

@main
struct ParsecAudit {
    @MainActor static var passed = 0
    @MainActor static let baseURL = URL(string: ProcessInfo.processInfo.environment["PARSEC_AUDIT_URL"]!)!

    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            var status: Int32 = 0
            do {
                try await run()
                print("PASS: \(passed) audit checks")
            } catch {
                print("FAIL: \(error.localizedDescription)")
                status = 1
            }
            exit(status)
        }
        application.run()
    }

    @MainActor static func expect(_ condition: Bool, _ name: String) throws {
        guard condition else { throw NSError(domain: "ParsecAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        passed += 1
        print("PASS: \(name)")
    }

    @MainActor static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        guard condition() else { throw NSError(domain: "ParsecAudit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for WebKit"]) }
    }

    @MainActor static func evaluate(_ script: String, in page: WebPage, world: WKContentWorld? = nil, arguments: [String: Any] = [:]) async throws -> Any? {
        try await page.webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: world ?? .defaultClient)
    }

    @MainActor static func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appending(path: "counts"))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    @MainActor static func run() async throws {
        try expect(!SavedCredential(host: "co.uk", account: "audit").matches(host: "attacker.co.uk"), "credentials reject public-suffix parents")
        try expect(!SavedCredential(host: "example.com", account: "audit").matches(host: "attacker.example.com"), "credentials reject subdomains")
        try expect(!SavedCredential(host: "login.example.com", account: "audit").matches(host: "example.com"), "credentials reject reverse parent matching")
        try expect(SavedCredential(host: "example.com", account: "audit").matches(host: "EXAMPLE.COM"), "credentials accept exact case-insensitive host")
        let queryURL = InputResolver.searchURL(for: "a&b#c+d")!
        try expect(URLComponents(url: queryURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a&b#c+d", "search query preserves separators")
        try expect(WebOrigin(url: URL(string: "https://example.com")!) == WebOrigin(url: URL(string: "https://example.com:443")!), "origin normalizes default port")
        try expect(WebOrigin(url: URL(string: "https://example.com:8443")!) != WebOrigin(url: URL(string: "https://example.com")!), "origin separates ports")
        try expect(!WebSecurityPolicy.isSecureEndpoint(URL(string: "http://remote.example")!), "API rejects remote cleartext")
        try expect(WebSecurityPolicy.isSecureEndpoint(baseURL), "API accepts loopback development server")
        try expect(!WebSecurityPolicy.isSecureEndpoint(URL(string: "https://user:password@example.com")!), "API rejects URL credentials")
        try expect(WebSecurityPolicy.downloadFilename("../../payload.command") == "payload.command", "download strips traversal")
        try expect(WebSecurityPolicy.downloadFilename("C:\\folder\\payload.command") == "payload.command", "download strips Windows paths")
        try expect(WebSecurityPolicy.downloadFilename("..") == "descarga", "download rejects parent filename")
        try expect(WebSecurityPolicy.downloadFilename(".zshrc") == "descarga.zshrc", "download rejects hidden dotfile destination")
        try expect(WebSecurityPolicy.downloadFilename("photo\u{202E}txt.exe") == "phototxt.exe", "download removes extension spoofing control")
        let profile = Profile(name: "Audit")
        let store = BrowserStore.shared
        store.profiles = [profile]
        store.spaces = [Space(title: "Audit", profileID: profile.id)]
        store.lastSpaceID = store.spaces[0].id
        store.settings.hasSeenWelcome = true
        store.settings.autoPictureInPicture = false
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "filterListsLastUpdate")
        UserDefaults.standard.set(UUID().uuidString, forKey: "filterListsVersion")
        let filterFolder = StorageConstants.applicationSupportURL.appending(path: "Filters", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: filterFolder, withIntermediateDirectories: true)
        try "invalid downloaded filter".write(to: filterFolder.appending(path: "easylist.txt"), atomically: true, encoding: .utf8)
        try "invalid downloaded filter".write(to: filterFolder.appending(path: "easyprivacy.txt"), atomically: true, encoding: .utf8)
        let privateID = UUID()
        let firstStore = WebConfigurationFactory.dataStore(profileID: privateID, isPrivate: true)
        let otherStore = WebConfigurationFactory.dataStore(profileID: UUID(), isPrivate: true)
        try expect(firstStore !== otherStore, "private windows have different data stores")
        try expect(firstStore === WebConfigurationFactory.dataStore(profileID: privateID, isPrivate: true), "private tabs share only their window data store")
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "audit", .value: "fixture"])!
        await firstStore.httpCookieStore.setCookie(cookie)
        try expect(await otherStore.httpCookieStore.allCookies().isEmpty, "private cookies do not cross windows")
        WebConfigurationFactory.releasePrivateData(profileID: privateID)
        try expect(firstStore !== WebConfigurationFactory.dataStore(profileID: privateID, isPrivate: true), "private store is released at window close")
        let privatePage = WebPage(profileID: privateID, isPrivate: true)
        privatePage.webView.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        privatePage.load(baseURL.appending(path: "private-page"))
        try await waitUntil { privatePage.hasCommittedNavigation && !privatePage.isLoading && !privatePage.title.isEmpty }
        try expect(await ContentBlocker.shared.waitUntilPrepared(), "corrupt downloaded filters fall back to bundled protection")
        try expect(store.history.allVisits(profileID: privateID).isEmpty, "private navigation leaves no history")
        try expect(!FileManager.default.fileExists(atPath: StorageConstants.applicationSupportURL.appending(path: "Favicons/127.0.0.1.png").path), "private navigation leaves no favicon file")
        _ = FaviconStore.shared.icon(for: baseURL, allowsNetwork: false)
        try await Task.sleep(for: .milliseconds(150))
        try expect((try await counts())["/favicon.ico"] == nil, "private favicon views make no requests")
        let frameCapture = AuditFrameCapture()
        let auditHost = AuditHost()
        privatePage.host = auditHost
        let controller = privatePage.webView.configuration.userContentController
        guard let docsMetricsScript = controller.userScripts.first(where: { $0.source == WebConfigurationFactory.googleDocsWindowMetricsScript }) else {
            throw NSError(domain: "ParsecAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Google Docs window metrics script missing"])
        }
        try expect(docsMetricsScript.injectionTime == .atDocumentStart && docsMetricsScript.isForMainFrameOnly, "Docs metrics run before its canvas renderer starts")
        let metricsFixture = """
        const location = { hostname: host };
        const window = { outerWidth: width, outerHeight: height, innerWidth: 816, innerHeight: 1056 };
        \(docsMetricsScript.source)
        window.innerWidth = 1024;
        window.innerHeight = 768;
        return [window.outerWidth, window.outerHeight];
        """
        try expect(try await evaluate(metricsFixture, in: privatePage, arguments: ["host": "docs.google.com", "width": 0, "height": 0]) as? [Int] == [1024, 768], "Docs missing window metrics follow viewport resizing")
        try expect(try await evaluate(metricsFixture, in: privatePage, arguments: ["host": "docs.google.com", "width": 1280, "height": 900]) as? [Int] == [1280, 900], "Docs valid native window metrics remain intact")
        try expect(try await evaluate(metricsFixture, in: privatePage, arguments: ["host": "other.example", "width": 0, "height": 0]) as? [Int] == [0, 0], "Docs window metric workaround leaves other sites unchanged")
        controller.add(frameCapture, contentWorld: .defaultClient, name: "auditFrame")
        controller.addUserScript(WKUserScript(source: "window.webkit.messageHandlers.auditFrame.postMessage(window === top ? 'main' : 'child');", injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient))
        _ = try await evaluate("window.webkit.messageHandlers.auditFrame.postMessage('main'); const frame = document.createElement('iframe'); frame.src = '/embedded'; document.body.appendChild(frame); return true;", in: privatePage)
        try await waitUntil { frameCapture.frames["main"] != nil && frameCapture.frames["child"] != nil }
        let mainFrame = frameCapture.frames["main"]!
        let childFrame = frameCapture.frames["child"]!
        let frameDecision = await withCheckedContinuation { continuation in
            privatePage.webView(privatePage.webView, requestMediaCapturePermissionFor: childFrame.securityOrigin, initiatedByFrame: childFrame, type: .camera) { continuation.resume(returning: $0) }
        }
        try expect(frameDecision == .deny && auditHost.permissionCount == 0, "embedded frame cannot inherit camera permission")
        let currentOrigin = WebOrigin(securityOrigin: mainFrame.securityOrigin)!
        store.setPermission(true, profileID: privateID, host: currentOrigin.identifier, kind: .camera)
        try expect(store.permissionDecision(profileID: privateID, host: "https://127.0.0.1:443", kind: .camera) == nil, "media grants do not cross scheme and port")
        auditHost.permissionResult = true
        auditHost.delaysPermission = true
        let permissionTask = Task { @MainActor in
            await withCheckedContinuation { continuation in
                privatePage.webView(privatePage.webView, requestMediaCapturePermissionFor: mainFrame.securityOrigin, initiatedByFrame: mainFrame, type: .camera) { continuation.resume(returning: $0) }
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        privatePage.load(baseURL.appending(path: "after-permission"))
        try expect(await permissionTask.value == .deny, "media grant is rejected after navigation during prompt")
        try await waitUntil { privatePage.webView.url?.path == "/after-permission" && !privatePage.isLoading }
        let observation = await PageDriver.observe(privatePage)
        try expect(!observation.elements.contains("fixture-secret") && !observation.elements.contains("fixture-card") && !observation.elements.contains("fixture-code"), "agent observation redacts sensitive field values")
        if let passwordLine = observation.elements.split(separator: "\n").first(where: { $0.contains("input[password]") }), let bracket = passwordLine.firstIndex(of: "]"), let identifier = Int(passwordLine[passwordLine.index(after: passwordLine.startIndex)..<bracket]) {
            let outcome = await PageDriver.type("replacement", into: identifier, submit: false, label: "Audit", from: nil, in: privatePage)
            if case .blocked = outcome { try expect(true, "agent refuses sensitive input") }
            else { try expect(false, "agent refuses sensitive input") }
        } else { try expect(false, "agent finds password field") }
        if let buttonLine = observation.elements.split(separator: "\n").first(where: { $0.contains("button") }), let bracket = buttonLine.firstIndex(of: "]"), let identifier = Int(buttonLine[buttonLine.index(after: buttonLine.startIndex)..<bracket]) {
            let outcome = await PageDriver.click(identifier, label: "Audit", allowsSubmit: false, from: nil, in: privatePage)
            if case .needsConfirmation = outcome { try expect(true, "agent gates button actions") }
            else { try expect(false, "agent gates button actions") }
        }
        do {
            try await privatePage.fill(SavedCredential(host: "127.0.0.1", account: "audit"))
            try expect(false, "credential fill rejects HTTP before authentication")
        } catch PasswordVaultError.unsafePage { try expect(true, "credential fill rejects HTTP before authentication") }
        privatePage.tearDown()
        let credentialPage = WebPage(profileID: UUID(), isPrivate: true)
        credentialPage.webView.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        credentialPage.webView.loadHTMLString("<title>Credential fixture</title><form><input autocomplete='username'><input id='password' type='password'></form>", baseURL: URL(string: "https://audit.invalid"))
        try await waitUntil { credentialPage.title == "Credential fixture" && !credentialPage.isLoading }
        let fillArguments: [String: Any] = ["username": "audit", "password": "audit-password", "expectedOrigin": "https://audit.invalid"]
        let documentID = try await evaluate("return window.parsecCredentialDocumentID;", in: credentialPage, world: WebConfigurationFactory.autofillWorld) as! String
        var matchingArguments = fillArguments
        matchingArguments["expectedDocumentID"] = documentID
        let fillScript = "return window.parsecFillCredentials(username, password, expectedDocumentID, expectedOrigin);"
        try expect(try await evaluate(fillScript, in: credentialPage, world: WebConfigurationFactory.autofillWorld, arguments: matchingArguments) as? Bool == true, "autofill succeeds for matching document and HTTPS origin")
        matchingArguments["expectedDocumentID"] = "stale-document"
        try expect(try await evaluate(fillScript, in: credentialPage, world: WebConfigurationFactory.autofillWorld, arguments: matchingArguments) as? Bool == false, "autofill rejects stale document identity")
        matchingArguments["expectedDocumentID"] = documentID
        matchingArguments["expectedOrigin"] = "https://different.invalid"
        try expect(try await evaluate(fillScript, in: credentialPage, world: WebConfigurationFactory.autofillWorld, arguments: matchingArguments) as? Bool == false, "autofill rejects changed origin")
        matchingArguments["expectedOrigin"] = "https://audit.invalid"
        _ = try await evaluate("document.querySelector('form').action = 'https://different.invalid'; return true;", in: credentialPage)
        try expect(try await evaluate(fillScript, in: credentialPage, world: WebConfigurationFactory.autofillWorld, arguments: matchingArguments) as? Bool == false, "autofill rejects cross-origin form destination")
        credentialPage.tearDown()
        let model = WindowModel()
        let commandQuery = "audit command selection"
        let commandTab = SidebarNode.tab(url: baseURL, title: commandQuery)
        model.currentSpace.today.append(commandTab)
        store.settings.showsSearchSuggestions = false
        let commandBar = CommandBarModel(windowModel: model, mode: .newTab, initialText: commandQuery)
        try expect(commandBar.results.first?.kind == .openTab(nodeID: commandTab.id), "command bar starts with the matching tab")
        commandBar.moveSelection(by: 1)
        let searchResult = commandBar.results[commandBar.selectedIndex]
        commandBar.query = commandQuery
        try expect(commandBar.selectedIndex == 1 && commandBar.results[1].id == searchResult.id && searchResult.kind == .url(InputResolver.searchURL(for: commandQuery)!), "unchanged query preserves the selected Google search")
        commandBar.moveSelection(by: 1)
        commandBar.query = commandQuery
        try expect(commandBar.results[commandBar.selectedIndex].kind == .askAssistant(commandQuery), "unchanged query preserves another selected result")
        commandBar.moveSelection(by: -1)
        try expect(commandBar.results[commandBar.selectedIndex].id == searchResult.id, "up arrow restores the previous result")
        commandBar.query = "changed audit command selection"
        try expect(commandBar.selectedIndex == 0 && commandBar.results.first?.id != searchResult.id, "changed query rebuilds results and resets selection")
        store.remove(commandTab.id)
        let favoriteTabs = (0..<10).map { SidebarNode.tab(url: baseURL, title: "Favorite \($0)") }
        profile.favorites = favoriteTabs
        let originalFavoriteIDs = favoriteTabs.map(\.id)
        let forwardDrop = SidebarDrop.handleFavorite([favoriteTabs[0].id.uuidString], model: model, location: CGPoint(x: 100, y: 22), pageIndex: 0, availableWidth: 194)
        try expect(forwardDrop && profile.favorites[1].id == favoriteTabs[0].id && profile.favorites[0].id == favoriteTabs[1].id, "favorite drop commits the pointer slot without preview state")
        SidebarDrop.handleFavorite([favoriteTabs[0].id.uuidString], model: model, location: CGPoint(x: 30, y: 22), pageIndex: 0, availableWidth: 194)
        try expect(profile.favorites.map(\.id) == originalFavoriteIDs, "backward favorite drop restores the requested order")
        SidebarDrop.handleFavorite([favoriteTabs[9].id.uuidString], model: model, location: CGPoint(x: 30, y: 22), pageIndex: 0, availableWidth: 194)
        try expect(profile.favorites.first?.id == favoriteTabs[9].id && profile.favorites.count == 10, "cross-page favorite drop retains every favorite")
        SidebarDrop.handleFavorite([favoriteTabs[9].id.uuidString], model: model, location: CGPoint(x: 170, y: 122), pageIndex: 1, availableWidth: 194)
        try expect(profile.favorites.map(\.id) == originalFavoriteIDs, "sparse-page drop clamps to the final favorite slot")
        SidebarDrop.handleFavorite([favoriteTabs[0].id.uuidString], model: model, location: CGPoint(x: 100, y: 22), pageIndex: 0, availableWidth: 194)
        store.saveNow()
        let savedStateURL = StorageConstants.applicationSupportURL.appending(path: StorageConstants.stateFileName)
        let savedState = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: savedStateURL))
        try expect(savedState.profiles.first?.favorites.map(\.id) == profile.favorites.map(\.id), "committed favorite order survives a disk round trip")
        profile.favorites = []
        let otherProfile = Profile(name: "Second audit profile")
        store.profiles.append(otherProfile)
        let otherSpace = Space(title: "Second audit space", profileID: otherProfile.id)
        let backgroundTab = SidebarNode.tab(url: nil)
        otherSpace.today.append(backgroundTab)
        store.spaces.append(otherSpace)
        let backgroundPage = model.loadPage(for: backgroundTab)
        try expect(backgroundPage.profileID == otherProfile.id && backgroundPage.webView.configuration.websiteDataStore.identifier == otherProfile.id, "background page keeps owning profile data store")
        let popup = model.openNewTab(from: backgroundPage, url: nil, configuration: nil, inBackground: true)
        try expect(popup?.configuration.websiteDataStore.identifier == otherProfile.id, "background popup keeps source profile")
        store.unloadPages(in: backgroundTab)
        let window = BrowserWindow(model: model)
        window.makeKeyAndOrderFront(nil)
        store.visibleNodeIDs = { model.visibleNodeIDs }
        let blank = model.openInNewTab(nil)
        model.open(baseURL.appending(path: "single-load"), mode: .navigate(nodeID: blank.id))
        try await waitUntil { blank.page?.hasCommittedNavigation == true && blank.page?.isLoading == false && blank.page?.title.isEmpty == false }
        try expect((try await counts())["/single-load"] == 1, "blank tab navigation issues one request")
        let page = blank.page!
        let actions = [BrowserAction(type: .open, url: "file:///etc/passwd", newTab: true), BrowserAction(type: .open, url: "data:text/html,audit", newTab: true)]
        try expect(await BrowserActionExecutor.run(actions, in: model).count == 2, "assistant refuses non-web destinations")
        let fillAction = BrowserAction(type: .fill, selector: "#password", value: "replacement")
        try expect(await BrowserActionExecutor.run([fillAction], in: model).count == 1, "assistant refuses password fill")
        _ = try await evaluate("location.href = 'parsec-http-continue:http://127.0.0.1:\(baseURL.port!)/bypass'; return true;", in: page)
        try await Task.sleep(for: .milliseconds(200))
        try expect((try await counts())["/bypass"] == nil, "page cannot forge HTTP exception")
        _ = try await evaluate("location.href = 'file:///etc/passwd'; return true;", in: page)
        try await Task.sleep(for: .milliseconds(200))
        try expect(page.webView.url?.scheme == "http", "remote page cannot navigate to local file")
        let before = try await counts()["/icon.png", default: 0]
        for _ in 0..<20 { FaviconStore.shared.updateIcon(host: "audit-icon", iconURL: baseURL.appending(path: "icon.png")) }
        try await waitUntil { FaviconStore.shared.icons["audit-icon"] != nil }
        for _ in 0..<20 { FaviconStore.shared.updateIcon(host: "audit-icon", iconURL: baseURL.appending(path: "icon.png")) }
        try await Task.sleep(for: .milliseconds(200))
        try expect((try await counts())["/icon.png", default: 0] - before == 1, "40 favicon requests are coalesced into one download")
        FaviconStore.shared.updateIcon(host: "oversized-icon", iconURL: baseURL.appending(path: "oversized.png"))
        try await Task.sleep(for: .milliseconds(300))
        try expect(FaviconStore.shared.icons["oversized-icon"] == nil, "oversized favicon rejected")
        FaviconStore.shared.updateIcon(host: "bad-icon", iconURL: baseURL.appending(path: "bad-icon"))
        try await Task.sleep(for: .milliseconds(200))
        for _ in 0..<20 { FaviconStore.shared.updateIcon(host: "bad-icon", iconURL: baseURL.appending(path: "bad-icon")) }
        try await Task.sleep(for: .milliseconds(200))
        try expect((try await counts())["/bad-icon"] == 1, "failed favicon requests observe retry cooldown")
        do {
            let request = URLRequest(url: baseURL.appending(path: "redirect"))
            _ = try await ServerSentEvents.lines(for: request)
            try expect(false, "API refuses redirects")
        } catch APIError.http(let status, _) { try expect(status == 302, "API refuses redirects") }
        try expect((try await counts())["/redirect-target"] == nil, "API never contacts redirect destination")
        blank.lastActiveAt = .distantPast
        store.settings.suspendAfterMinutes = 1
        store.runLifecycleTick()
        try await Task.sleep(for: .milliseconds(100))
        try expect(blank.page === page, "lifecycle preserves visible tab")
        _ = model.openInNewTab(nil)
        blank.lastActiveAt = Date().addingTimeInterval(-120)
        store.runLifecycleTick()
        model.select(blank)
        try await Task.sleep(for: .milliseconds(200))
        try expect(blank.page === page, "lifecycle preserves tab selected during media callback")
        let playbackConfiguration = WebConfigurationFactory.makeConfiguration(profileID: model.profileID, isPrivate: false)
        playbackConfiguration.mediaTypesRequiringUserActionForPlayback = []
        let audioNode = SidebarNode.tab(url: baseURL.appending(path: "audio"))
        let audioPage = model.loadPage(for: audioNode, configuration: playbackConfiguration)
        model.adopt(audioNode)
        audioPage.load(baseURL.appending(path: "audio"))
        try await waitUntil { audioPage.hasCommittedNavigation && !audioPage.isLoading && !audioPage.title.isEmpty }
        _ = try await evaluate("const audio = new Audio('/tone.wav'); audio.loop = true; window.auditAudio = audio; await audio.play(); return true;", in: audioPage)
        let playbackState = await withCheckedContinuation { continuation in audioPage.webView.requestMediaPlaybackState { continuation.resume(returning: $0) } }
        try expect(playbackState == .playing, "fixture starts real WebKit media playback")
        model.select(blank)
        audioNode.lastActiveAt = .distantPast
        store.runLifecycleTick()
        try await Task.sleep(for: .milliseconds(200))
        try expect(audioNode.page === audioPage && model.currentSpace.today.contains(where: { $0 === audioNode }), "suspension and archive preserve playing audio")
        _ = try await evaluate("window.auditAudio.pause(); return true;", in: audioPage)
        store.runLifecycleTick()
        try await waitUntil { !model.currentSpace.today.contains(where: { $0 === audioNode }) }
        try expect(audioNode.page == nil, "idle background tab releases WebKit after playback stops")
        let downloadFolder = StorageConstants.applicationSupportURL.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        store.settings.downloadFolderPath = downloadFolder.path
        model.open(baseURL.appending(path: "download"), mode: .navigate(nodeID: blank.id))
        try await waitUntil { DownloadManager.shared.items.first?.state == .finished }
        let download = DownloadManager.shared.items[0]
        try expect(download.destinationURL.deletingLastPathComponent() == downloadFolder, "download stays inside configured folder")
        let quarantine = try download.destinationURL.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        try expect(quarantine != nil, "completed download carries macOS quarantine")
        let privateDownloadPage = WebPage(profileID: UUID(), isPrivate: true)
        privateDownloadPage.load(baseURL.appending(path: "download"))
        try await waitUntil { DownloadManager.shared.items.first?.isPrivate == true && DownloadManager.shared.items.first?.state == .finished }
        let privateDownload = DownloadManager.shared.items[0]
        let persistedDownloads = try String(contentsOf: StorageConstants.applicationSupportURL.appending(path: "downloads.json"), encoding: .utf8)
        try expect(!persistedDownloads.contains(privateDownload.id.uuidString), "private download is excluded from persistent history")
        privateDownloadPage.tearDown()
        model.open(baseURL.appending(path: "ui"), mode: .navigate(nodeID: blank.id))
        try await waitUntil { page.webView.url?.path == "/ui" && !page.isLoading && !page.title.isEmpty }
        let reportURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PARSEC_AUDIT_REPORT_DIR"]!)
        let image = try await page.webView.takeSnapshot(configuration: nil)
        if let data = image.pngData {
            try data.write(to: reportURL.appending(path: "page.png"))
        }
        if let contentView = window.contentView, let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: reportURL.appending(path: "window.png"))
        }
        window.close()
        store.allTabNodes.forEach(store.unloadPage)
    }
}
