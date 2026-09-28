import Foundation
import Observation

@MainActor
@Observable
final class LocalModels {
    struct Suggestion: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    static let shared = LocalModels()
    nonisolated static let defaultModel = "llama3.2"
    static let websiteURL = URL(string: "https://ollama.com")
    static let downloadURL = URL(string: "https://ollama.com/download")!
    static let chatEndpoint = OpenAIAPIClient.endpoint(forBaseURL: serverURL.appending(path: "v1").absoluteString)
    static let suggestions = [
        Suggestion(name: "llama3.2", detail: "Meta · 2 GB · rápido para el día a día"),
        Suggestion(name: "gemma3:4b", detail: "Google · 3 GB · multilingüe"),
        Suggestion(name: "qwen3:8b", detail: "Alibaba · 5 GB · razona paso a paso"),
        Suggestion(name: "mistral", detail: "Mistral · 4 GB · buen español"),
    ]
    private static let serverURL = URL(string: "http://localhost:11434")!
    private static let tagsPath = "api/tags"
    private static let pullPath = "api/pull"
    private static let deletePath = "api/delete"
    private static let successStatus = "success"

    private(set) var installed: [String] = []
    private(set) var isServerRunning = false
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var errorMessage: String?

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.serverURL.appending(path: Self.tagsPath))
            let models = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]] ?? []
            installed = models.compactMap { $0["name"] as? String }.sorted()
            isServerRunning = true
        } catch {
            installed = []
            isServerRunning = false
        }
    }

    func isInstalled(_ name: String) -> Bool {
        installed.contains { $0 == name || $0 == name + ":latest" }
    }

    func download(_ name: String) {
        guard downloadProgress[name] == nil else { return }
        downloadProgress[name] = 0
        errorMessage = nil
        Task {
            do {
                try await pull(name)
            } catch {
                errorMessage = "No se pudo descargar \(name): \(error.localizedDescription)"
            }
            downloadProgress[name] = nil
            await refresh()
        }
    }

    func remove(_ name: String) {
        var request = URLRequest(url: Self.serverURL.appending(path: Self.deletePath))
        request.httpMethod = "DELETE"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name])
        Task {
            _ = try? await URLSession.shared.data(for: request)
            await refresh()
        }
    }

    private func pull(_ name: String) async throws {
        var request = URLRequest(url: Self.serverURL.appending(path: Self.pullPath))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name])
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        for try await line in bytes.lines {
            guard let event = ServerSentEvents.json(line) else { continue }
            if let message = event["error"] as? String { throw APIError.http(status: 0, body: message) }
            if let total = event["total"] as? Double, let completed = event["completed"] as? Double, total > 0 {
                downloadProgress[name] = completed / total
            }
            if event["status"] as? String == Self.successStatus { return }
        }
    }
}
