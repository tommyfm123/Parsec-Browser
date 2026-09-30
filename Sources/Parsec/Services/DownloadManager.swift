import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: String, Codable {
        case inProgress
        case finished
        case failed
    }

    let id: UUID
    let filename: String
    let destinationURL: URL
    let createdAt: Date
    var fractionCompleted = 0.0
    var state = State.inProgress
    @ObservationIgnored var progressObservation: NSKeyValueObservation?

    init(id: UUID = UUID(), filename: String, destinationURL: URL, createdAt: Date = Date(), state: State = .inProgress, fractionCompleted: Double = 0) {
        self.id = id
        self.filename = filename
        self.destinationURL = destinationURL
        self.createdAt = createdAt
        self.state = state
        self.fractionCompleted = fractionCompleted
    }
}

@MainActor
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private static let fallbackFilename = "descarga"
    private static let riskyExtensions: Set<String> = ["app", "pkg", "mpkg", "dmg", "command", "sh", "zsh", "tool", "terminal", "scpt", "workflow", "jar", "exe", "msi", "bat", "iso", "webloc", "fileloc"]
    private static let persistenceURL = StorageConstants.applicationSupportURL.appending(path: "downloads.json")

    private(set) var items: [DownloadItem] = []
    @ObservationIgnored private var itemsByDownload: [ObjectIdentifier: DownloadItem] = [:]

    override init() {
        super.init()
        items = Self.loadItems()
        for item in items where item.state == .inProgress { item.state = .failed }
        persistItems()
    }

    var activeCount: Int { items.filter { $0.state == .inProgress }.count }

    static var downloadFolderURL: URL {
        BrowserStore.shared.settings.downloadFolderPath.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let filename = suggestedFilename.isEmpty ? Self.fallbackFilename : suggestedFilename
        guard confirmIfRisky(filename, source: response.url?.host() ?? "") else { return completionHandler(nil) }
        let destinationURL = uniqueDestination(for: filename)
        let item = DownloadItem(filename: destinationURL.lastPathComponent, destinationURL: destinationURL)
        item.progressObservation = download.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in item.fractionCompleted = fraction }
        }
        items.insert(item, at: 0)
        itemsByDownload[ObjectIdentifier(download)] = item
        persistItems()
        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download, state: .finished)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, state: .failed)
    }

    func reveal(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.destinationURL])
    }

    func open(_ item: DownloadItem) {
        NSWorkspace.shared.open(item.destinationURL)
    }

    func clearFinished() {
        items.removeAll { $0.state != .inProgress }
        persistItems()
    }

    func delete(_ item: DownloadItem) throws {
        guard item.state != .inProgress else { return }
        if FileManager.default.fileExists(atPath: item.destinationURL.path) {
            try FileManager.default.removeItem(at: item.destinationURL)
        }
        items.removeAll { $0.id == item.id }
        persistItems()
    }

    private func confirmIfRisky(_ filename: String, source: String) -> Bool {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        guard BrowserStore.shared.settings.warnsBeforeRiskyDownloads, Self.riskyExtensions.contains(fileExtension) else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "¿Descargar “\(filename)”?"
        alert.informativeText = "Es una app, instalador o script de \(source). Descárgalo solo si confías en el sitio. macOS lo revisará al abrirlo."
        alert.addButton(withTitle: "Descargar")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func quarantine(_ item: DownloadItem, source: URL?) {
        var properties: [String: Any] = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload, kLSQuarantineAgentNameKey as String: "Parsec"]
        properties[kLSQuarantineDataURLKey as String] = source
        var fileURL = item.destinationURL
        var values = URLResourceValues()
        values.quarantineProperties = properties
        try? fileURL.setResourceValues(values)
    }

    private func finish(_ download: WKDownload, state: DownloadItem.State) {
        guard let item = itemsByDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if state == .finished { quarantine(item, source: download.originalRequest?.url) }
        item.state = state
        item.fractionCompleted = state == .finished ? 1 : item.fractionCompleted
        item.progressObservation = nil
        persistItems()
    }

    private func persistItems() {
        do {
            let records = items.map(StoredDownload.init)
            let data = try JSONEncoder().encode(records)
            try data.write(to: Self.persistenceURL, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }

    private static func loadItems() -> [DownloadItem] {
        guard let data = try? Data(contentsOf: persistenceURL), let records = try? JSONDecoder().decode([StoredDownload].self, from: data) else { return [] }
        return records.map { record in
            DownloadItem(id: record.id, filename: record.filename, destinationURL: record.destinationURL, createdAt: record.createdAt, state: record.state, fractionCompleted: record.fractionCompleted)
        }
    }

    private struct StoredDownload: Codable {
        let id: UUID
        let filename: String
        let destinationURL: URL
        let createdAt: Date
        let state: DownloadItem.State
        let fractionCompleted: Double

        @MainActor init(item: DownloadItem) {
            id = item.id
            filename = item.filename
            destinationURL = item.destinationURL
            createdAt = item.createdAt
            state = item.state
            fractionCompleted = item.fractionCompleted
        }
    }

    private func uniqueDestination(for filename: String) -> URL {
        let downloadsURL = Self.downloadFolderURL
        let baseName = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var candidate = downloadsURL.appending(path: filename)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            suffix += 1
            let numberedName = "\(baseName) (\(suffix))" + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
            candidate = downloadsURL.appending(path: numberedName)
        }
        return candidate
    }
}
