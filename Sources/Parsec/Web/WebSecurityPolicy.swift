import Foundation
import WebKit

struct WebOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              WebSecurityPolicy.isWebURL(url), url.user == nil, url.password == nil else { return nil }
        self.scheme = scheme
        self.host = host
        port = url.port ?? (scheme == WebConstants.httpsScheme ? 443 : 80)
    }

    var identifier: String { "\(scheme)://\(host):\(port)" }
    var allowsCredentials: Bool { scheme == WebConstants.httpsScheme && port == 443 }
    var javascriptOrigin: String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let defaultPort = scheme == WebConstants.httpsScheme ? 443 : 80
        if port != defaultPort { components.port = port }
        return components.string ?? ""
    }
}

enum WebSecurityPolicy {
    static let sensitiveFieldScript = """
        const isSensitiveField = (element) => element.type === 'password' || element.type === 'file' || /cc-|card|password|one-time-code/i.test(element.getAttribute('autocomplete') || '');
        """
    static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == WebConstants.httpScheme || scheme == WebConstants.httpsScheme) && !(url.host ?? "").isEmpty
    }

    static func isSecureEndpoint(_ url: URL) -> Bool {
        guard let origin = WebOrigin(url: url) else { return false }
        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
        return origin.scheme == WebConstants.httpsScheme || loopbackHosts.contains(origin.host)
    }

    static func downloadFilename(_ suggested: String) -> String {
        let leaf = suggested.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let sanitized = String(leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202D}\u{202E}\u{202C}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else { return "descarga" }
        return sanitized.hasPrefix(".") ? "descarga" + sanitized : sanitized
    }
}

extension WebOrigin {
    init?(securityOrigin: WKSecurityOrigin) {
        var components = URLComponents()
        components.scheme = securityOrigin.protocol
        components.host = securityOrigin.host
        if securityOrigin.port > 0 { components.port = securityOrigin.port }
        guard let url = components.url else { return nil }
        self.init(url: url)
    }
}
