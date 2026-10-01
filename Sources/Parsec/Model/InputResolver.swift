import Foundation

enum InputResolver {
    private static let explicitSchemes: Set<String> = ["http", "https", "file", "about", "data"]
    private static let hostPortSeparator: Character = ":"

    static func destination(for rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if let explicitURL = explicitURL(from: input) { return explicitURL }
        if looksLikeHost(input) { return URL(string: schemeForHost(input) + "://" + input) }
        return searchURL(for: input)
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: WebConstants.googleSearchURL)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func isLocalHost(_ host: String) -> Bool {
        WebConstants.localHosts.contains(host) || WebConstants.localHostSuffixes.contains { host.hasSuffix($0) }
    }

    private static func explicitURL(from input: String) -> URL? {
        guard !input.contains(" "), let url = URL(string: input), let scheme = url.scheme?.lowercased() else { return nil }
        guard explicitSchemes.contains(scheme) else { return nil }
        let isWebScheme = scheme == WebConstants.httpScheme || scheme == WebConstants.httpsScheme
        let hasHost = !(url.host() ?? "").isEmpty
        return !isWebScheme || hasHost ? url : nil
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        let hostPart = hostComponent(of: input)
        if isLocalHost(hostPart) { return true }
        let labels = hostPart.split(separator: ".")
        let hasTopLevelDomain = labels.count >= 2 && (labels.last?.count ?? 0) >= 2
        let hasOnlyHostCharacters = hostPart.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return hasTopLevelDomain && hasOnlyHostCharacters
    }

    private static func hostComponent(of input: String) -> String {
        let beforePath = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? input
        return beforePath.split(separator: hostPortSeparator, maxSplits: 1).first.map(String.init)?.lowercased() ?? beforePath
    }

    private static func schemeForHost(_ input: String) -> String {
        isLocalHost(hostComponent(of: input)) ? WebConstants.httpScheme : WebConstants.httpsScheme
    }
}
