import AppKit
import Observation

@MainActor
@Observable
final class FaviconStore {
    static let shared = FaviconStore()
    private static let pngExtension = "png"
    private static let iconLinkPattern = #/<link\b[^>]*\brel\s*=\s*["'][^"']*icon[^"']*["'][^>]*>/#.ignoresCase()
    private static let hrefPattern = #/\bhref\s*=\s*(["'])(.+?)\1/#.ignoresCase()

    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private var requestedHosts: Set<String> = []
    @ObservationIgnored private let folderURL: URL = {
        let url = StorageConstants.applicationSupportURL.appending(path: StorageConstants.faviconFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func icon(for url: URL?) -> NSImage? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        if let cached = icons[host] { return cached }
        guard !requestedHosts.contains(host) else { return nil }
        let iconURL = defaultIconURL(for: url)
        Task { self.requestIcon(host: host, iconURL: iconURL) }
        return nil
    }

    func updateIcon(host: String, iconURL: URL) {
        requestedHosts.remove(host)
        requestIcon(host: host, iconURL: iconURL, replacesExisting: true)
    }

    private func requestIcon(host: String, iconURL: URL?, replacesExisting: Bool = false) {
        guard !requestedHosts.contains(host) else { return }
        requestedHosts.insert(host)
        let fileURL = folderURL.appending(path: host + "." + Self.pngExtension)
        if !replacesExisting, let diskImage = NSImage(contentsOf: fileURL) {
            icons[host] = diskImage
            return
        }
        guard let iconURL else { return }
        Task {
            await download(iconURL: iconURL, host: host, fileURL: fileURL)
        }
    }

    private func download(iconURL: URL, host: String, fileURL: URL) async {
        do {
            let downloaded = try await fetchImage(from: iconURL)
            let discovered = downloaded == nil ? try await fetchDiscoveredImage(near: iconURL) : nil
            guard let image = downloaded ?? discovered else { return }
            icons[host] = image
            try? image.pngData?.write(to: fileURL)
        } catch {
            requestedHosts.remove(host)
        }
    }

    private func fetchImage(from url: URL) async throws -> NSImage? {
        let (data, response) = try await URLSession.shared.data(from: url)
        let isSuccess = ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400
        guard isSuccess, let image = NSImage(data: data), image.isValid else { return nil }
        return image
    }

    private func fetchDiscoveredImage(near url: URL) async throws -> NSImage? {
        guard let rootURL = URL(string: "/", relativeTo: url) else { return nil }
        let (data, _) = try await URLSession.shared.data(from: rootURL)
        guard let html = String(data: data, encoding: .utf8), let linkedURL = Self.linkedIconURL(in: html, relativeTo: rootURL), linkedURL != url else { return nil }
        return try await fetchImage(from: linkedURL)
    }

    private static func linkedIconURL(in html: String, relativeTo baseURL: URL) -> URL? {
        guard let tag = html.firstMatch(of: iconLinkPattern)?.output,
              let href = String(tag).firstMatch(of: hrefPattern)?.output.2
        else { return nil }
        return URL(string: String(href), relativeTo: baseURL)?.absoluteURL
    }

    private func defaultIconURL(for url: URL?) -> URL? {
        guard let url, let scheme = url.scheme, let host = url.host() else { return nil }
        let isWeb = scheme == WebConstants.httpScheme || scheme == WebConstants.httpsScheme
        return isWeb ? URL(string: "\(scheme)://\(host)\(WebConstants.faviconPath)") : nil
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
