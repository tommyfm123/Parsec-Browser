import AppKit
import ImageIO
import Observation

@MainActor
@Observable
final class FaviconStore {
    static let shared = FaviconStore()
    private static let pngExtension = "png"
    private static let retryInterval: TimeInterval = 60
    nonisolated private static let maximumIconBytes = 512 * 1024
    nonisolated private static let maximumIconDimension = 64
    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private var requestedURLs: [String: URL] = [:]
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()
    @ObservationIgnored private let folderURL: URL = {
        let url = StorageConstants.applicationSupportURL.appending(path: StorageConstants.faviconFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    @ObservationIgnored private let legacyFolderURL = StorageConstants.applicationSupportURL.appending(path: StorageConstants.legacyFaviconFolderName, directoryHint: .isDirectory)

    func icon(for url: URL?, allowsNetwork: Bool = true) -> NSImage? {
        guard let url, WebSecurityPolicy.isWebURL(url), let host = url.host, !host.isEmpty else { return nil }
        if let cached = icons[host] { return cached }
        guard allowsNetwork else { return nil }
        guard tasks[host] == nil else { return nil }
        let fileURL = cachedFileURL(host: host)
        if let diskImage = NSImage(contentsOf: fileURL) {
            icons[host] = diskImage
            return diskImage
        }
        let legacyImage = NSImage(contentsOf: legacyFolderURL.appending(path: fileURL.lastPathComponent))
        if let legacyImage { icons[host] = legacyImage }
        guard let iconURL = URL(string: WebConstants.faviconPath, relativeTo: url)?.absoluteURL else { return legacyImage }
        requestIcon(host: host, iconURL: iconURL)
        return legacyImage
    }

    func updateIcon(host: String, iconURL: URL) {
        guard WebSecurityPolicy.isWebURL(iconURL) else { return }
        requestIcon(host: host, iconURL: iconURL)
    }

    private func cachedFileURL(host: String) -> URL {
        folderURL.appending(path: WebSecurityPolicy.downloadFilename(host) + "." + Self.pngExtension)
    }

    private func requestIcon(host: String, iconURL: URL) {
        let isSameRequest = requestedURLs[host] == iconURL
        guard !(isSameRequest && (icons[host] != nil || tasks[host] != nil)) else { return }
        if let failureDate = failedAt[host], Date().timeIntervalSince(failureDate) < Self.retryInterval { return }
        tasks[host]?.cancel()
        requestedURLs[host] = iconURL
        let fileURL = cachedFileURL(host: host)
        tasks[host] = Task {
            do {
                let data = try await Self.fetchIcon(from: iconURL, session: session)
                try Task.checkCancellation()
                guard requestedURLs[host] == iconURL else { return }
                let image = NSImage(data: data)
                guard let image else { throw URLError(.cannotDecodeContentData) }
                icons[host] = image
                try data.write(to: fileURL, options: .atomic)
                failedAt[host] = nil
                tasks[host] = nil
            } catch {
                guard !Task.isCancelled, requestedURLs[host] == iconURL else { return }
                failedAt[host] = Date()
                tasks[host] = nil
            }
        }
    }

    nonisolated private static func fetchIcon(from url: URL, session: URLSession) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              response.expectedContentLength <= maximumIconBytes else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumIconBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        guard let thumbnail = rasterThumbnail(from: data) ?? vectorThumbnail(from: data) else { throw URLError(.cannotDecodeContentData) }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else { throw URLError(.cannotDecodeContentData) }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw URLError(.cannotDecodeContentData) }
        return encoded as Data
    }

    nonisolated private static func rasterThumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, largestFrameIndex(in: source), [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumIconDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    nonisolated private static func vectorThumbnail(from data: Data) -> CGImage? {
        var renderRect = CGRect(x: 0, y: 0, width: maximumIconDimension, height: maximumIconDimension)
        return NSImage(data: data)?.cgImage(forProposedRect: &renderRect, context: nil, hints: nil)
    }

    nonisolated private static func largestFrameIndex(in source: CGImageSource) -> Int {
        let frameIndices = 0..<CGImageSourceGetCount(source)
        return frameIndices.max { frameWidth(at: $0, in: source) < frameWidth(at: $1, in: source) } ?? 0
    }

    nonisolated private static func frameWidth(at index: Int, in source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
