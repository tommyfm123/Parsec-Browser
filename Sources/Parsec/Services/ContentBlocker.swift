import Foundation
import WebKit

@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()
    private static let filterSources: [(name: String, url: URL)] = [
        (StorageConstants.easyListResource, URL(string: "https://easylist.to/easylist/easylist.txt")!),
        (StorageConstants.easyPrivacyResource, URL(string: "https://easylist.to/easylist/easyprivacy.txt")!),
    ]
    private static let bundledVersion = "bundled-1"
    private static let versionDefaultsKey = "filterListsVersion"
    private static let lastUpdateDefaultsKey = "filterListsLastUpdate"
    private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let filtersFolderName = "Filters"
    nonisolated private static let domainRulePrefix = "||"
    nonisolated private static let domainRuleSuffix = "^"
    nonisolated private static let thirdPartyOption = "$third-party"
    nonisolated private static let optionSeparator: Character = "$"

    private static let thirdPartyCookieListIdentifier = "third-party-cookies-1"
    private static let thirdPartyCookieRules = #"[{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block-cookies"}}]"#

    private static let googleOneTapListIdentifier = "google-one-tap-1"
    private static let googleOneTapRules = ##"[{"trigger":{"url-filter":"^https?://accounts\\.google\\.com/gsi/iframe/select"},"action":{"type":"block"}},{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"#credential_picker_container, #credential_picker_iframe"}}]"##

    private(set) var ruleLists: [WKContentRuleList] = []
    private(set) var cookieRuleList: WKContentRuleList?
    private(set) var googleOneTapRuleList: WKContentRuleList?
    private let controllers = NSMapTable<WKUserContentController, NSNumber>.weakToStrongObjects()
    private var preparationTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let filtersFolderURL: URL = {
        let url = StorageConstants.applicationSupportURL.appending(path: filtersFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var currentVersion: String {
        defaults.string(forKey: Self.versionDefaultsKey) ?? Self.bundledVersion
    }

    func prepare() {
        guard preparationTask == nil else { return }
        preparationTask = Task {
            cookieRuleList = await cachedRuleList(identifier: Self.thirdPartyCookieListIdentifier, rules: Self.thirdPartyCookieRules)
            googleOneTapRuleList = await cachedRuleList(identifier: Self.googleOneTapListIdentifier, rules: Self.googleOneTapRules)
            await compileAll(version: currentVersion)
            updateControllers()
            Task { await refreshIfStale() }
        }
    }

    func waitUntilPrepared() async -> Bool {
        prepare()
        await preparationTask?.value
        return cookieRuleList != nil && ruleLists.count == Self.filterSources.count
    }

    private func cachedRuleList(identifier: String, rules: String) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) { return cached }
        return try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
    }

    func install(on controller: WKUserContentController, includesBlocker: Bool) {
        controllers.setObject(NSNumber(value: includesBlocker), forKey: controller)
        applyRules(on: controller, includesBlocker: includesBlocker)
    }

    private func applyRules(on controller: WKUserContentController, includesBlocker: Bool) {
        controller.removeAllContentRuleLists()
        cookieRuleList.map(controller.add)
        if BrowserStore.shared.settings.hidesGoogleOneTap { googleOneTapRuleList.map(controller.add) }
        guard includesBlocker else { return }
        ruleLists.forEach(controller.add)
    }

    private func updateControllers() {
        let registeredControllers = controllers.keyEnumerator()
        while let controller = registeredControllers.nextObject() as? WKUserContentController {
            let includesBlocker = controllers.object(forKey: controller)?.boolValue ?? true
            applyRules(on: controller, includesBlocker: includesBlocker)
        }
    }

    private func compileAll(version: String) async {
        var compiledLists: [WKContentRuleList] = []
        for source in Self.filterSources {
            if let ruleList = await loadOrCompile(listName: source.name, version: version) {
                compiledLists.append(ruleList)
            }
        }
        guard compiledLists.count == Self.filterSources.count else { return }
        ruleLists = compiledLists
        updateControllers()
    }

    private func refreshIfStale() async {
        let lastUpdate = defaults.double(forKey: Self.lastUpdateDefaultsKey)
        guard Date().timeIntervalSince1970 - lastUpdate > Self.refreshInterval else { return }
        for source in Self.filterSources {
            guard let (data, response) = try? await URLSession.shared.data(from: source.url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            try? data.write(to: downloadedFileURL(for: source.name), options: .atomic)
        }
        let newVersion = String(Int(Date().timeIntervalSince1970))
        defaults.set(newVersion, forKey: Self.versionDefaultsKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastUpdateDefaultsKey)
        await compileAll(version: newVersion)
    }

    private func loadOrCompile(listName: String, version: String) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        let identifier = listName + "-" + version
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        for contents in filterContents(listName: listName) {
            let encodedRules = await Task.detached { Self.webKitRules(fromFilterList: contents) }.value
            guard encodedRules != "[]" else { continue }
            if let compiled = try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encodedRules) { return compiled }
        }
        return nil
    }

    private func filterContents(listName: String) -> [String] {
        let downloadedURL = downloadedFileURL(for: listName)
        let bundledURL = Bundle.main.url(forResource: listName, withExtension: StorageConstants.filterListExtension)
        return [downloadedURL, bundledURL].compactMap { sourceURL in
            sourceURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }

    private func downloadedFileURL(for listName: String) -> URL {
        filtersFolderURL.appending(path: listName + "." + StorageConstants.filterListExtension)
    }

    nonisolated static func webKitRules(fromFilterList contents: String) -> String {
        var rules: [String] = []
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let rule = webKitRule(fromFilterLine: String(line)) else { continue }
            rules.append(rule)
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    nonisolated private static func webKitRule(fromFilterLine line: String) -> String? {
        guard line.hasPrefix(domainRulePrefix) else { return nil }
        let isThirdPartyOnly = line.hasSuffix(domainRuleSuffix + thirdPartyOption)
        let hasOtherOptions = line.contains(optionSeparator) && !isThirdPartyOnly
        guard !hasOtherOptions else { return nil }
        let body = line.dropFirst(domainRulePrefix.count)
        let domain = body.split(separator: Character(domainRuleSuffix), maxSplits: 1).first.map(String.init) ?? ""
        let isPlainDomain = !domain.isEmpty && domain.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        let isDomainOnlyRule = body == domain + domainRuleSuffix || isThirdPartyOnly && body == domain + domainRuleSuffix + thirdPartyOption
        guard isPlainDomain, isDomainOnlyRule else { return nil }
        let escapedDomain = domain.replacingOccurrences(of: ".", with: "\\\\.")
        let loadType = isThirdPartyOnly ? ",\"load-type\":[\"third-party\"]" : ""
        return "{\"trigger\":{\"url-filter\":\"^[^:]+://([^/]*\\\\.)?\(escapedDomain)[/:]\"\(loadType)},\"action\":{\"type\":\"block\"}}"
    }
}
