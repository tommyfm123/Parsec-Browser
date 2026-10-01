import WebKit

@MainActor
enum WebConfigurationFactory {
    static let autofillWorld = WKContentWorld.world(name: "parsec-autofill")
    static let autofillHandlerName = "parsecAutofill"
    static let linkPreviewWorld = WKContentWorld.world(name: "parsec-linkpreview")
    static let linkPreviewHandlerName = "parsecLinkPreview"
    private static let linkPreviewResourceName = "linkpreview"
    private static let autofillResourceName = "autofill"
    private static let javaScriptExtension = "js"
    private static let developerExtrasKey = "developerExtrasEnabled"
    private static let pictureInPictureKey = "allowsPictureInPictureMediaPlayback"
    private static let cacheDataTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
    private static let applicationNameForUserAgent = "Version/19.0 Safari/605.1.15"
    private static var dataStores: [UUID: WKWebsiteDataStore] = [:]
    private static var privateDataStores: [UUID: WKWebsiteDataStore] = [:]
    private static let autofillScriptSource: String = {
        guard let url = Bundle.main.url(forResource: autofillResourceName, withExtension: javaScriptExtension) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private static let linkPreviewScriptSource: String = {
        guard let url = Bundle.main.url(forResource: linkPreviewResourceName, withExtension: javaScriptExtension) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    static func dataStore(profileID: UUID, isPrivate: Bool) -> WKWebsiteDataStore {
        if isPrivate {
            if let existing = privateDataStores[profileID] { return existing }
            let store = WKWebsiteDataStore.nonPersistent()
            privateDataStores[profileID] = store
            return store
        }
        if let existing = dataStores[profileID] { return existing }
        let store = WKWebsiteDataStore(forIdentifier: profileID)
        dataStores[profileID] = store
        return store
    }

    static func makeConfiguration(profileID: UUID, isPrivate: Bool) -> WKWebViewConfiguration {
        makeConfiguration(dataStore: dataStore(profileID: profileID, isPrivate: isPrivate))
    }

    static func makeIsolatedConfiguration() -> WKWebViewConfiguration {
        makeConfiguration(dataStore: .nonPersistent())
    }

    private static func makeConfiguration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = BrowserStore.shared.settings.warnsAboutFraudulentSites
        configuration.preferences.setValue(BrowserStore.shared.settings.developerMode, forKey: developerExtrasKey)
        configuration.preferences.setValue(true, forKey: pictureInPictureKey)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.userContentController = makeUserContentController()
        return configuration
    }

    static func releasePrivateData(profileID: UUID) {
        privateDataStores[profileID] = nil
    }

    static func deleteData(profileID: UUID) async {
        let store = dataStore(profileID: profileID, isPrivate: false)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    static func deleteCaches(profileIDs: [UUID]) async {
        for profileID in profileIDs {
            await dataStore(profileID: profileID, isPrivate: false).removeData(ofTypes: cacheDataTypes, modifiedSince: .distantPast)
        }
    }

    static func deleteData(host: String, profileID: UUID) async {
        let store = dataStore(profileID: profileID, isPrivate: false)
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let matching = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching)
    }

    private static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        let autofillScript = WKUserScript(source: autofillScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: autofillWorld)
        controller.addUserScript(autofillScript)
        controller.add(AutofillMessageRouter.shared, contentWorld: autofillWorld, name: autofillHandlerName)
        let linkPreviewScript = WKUserScript(source: linkPreviewScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: linkPreviewWorld)
        controller.addUserScript(linkPreviewScript)
        controller.add(LinkPreviewMessageRouter.shared, contentWorld: linkPreviewWorld, name: linkPreviewHandlerName)
        controller.addUserScript(AutoPictureInPicture.intentTrackingScript)
        ContentBlocker.shared.install(on: controller, includesBlocker: true)
        return controller
    }
}

@MainActor
final class AutofillMessageRouter: NSObject, WKScriptMessageHandler {
    static let shared = AutofillMessageRouter()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let webView = message.webView, let page = WebPage.page(for: webView) else { return }
        guard let origin = WebOrigin(securityOrigin: message.frameInfo.securityOrigin) else { return }
        page.handleAutofillMessage(message.body, origin: origin)
    }
}
