import Foundation
import Observation

struct StoredSource: Codable, Hashable {
    let title: String
    let url: URL
}

struct StoredMessage: Codable {
    let isUser: Bool
    let text: String
    let isError: Bool
    let isBrowsing: Bool
    let contextLabels: [String]
    let sources: [StoredSource]
}

struct StoredConversation: Codable, Identifiable {
    private static let previewLength = 140

    let id: UUID
    let profileID: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let sessionID: String?
    let messages: [StoredMessage]

    var preview: String {
        let answer = messages.last { !$0.isUser && !$0.isError }?.text ?? ""
        return String(answer.replacingOccurrences(of: "\n", with: " ").prefix(Self.previewLength))
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || title.localizedStandardContains(query)
            || messages.contains { $0.text.localizedStandardContains(query) }
    }
}

@MainActor
@Observable
final class ConversationStore {
    static let shared = ConversationStore()
    private static let folderName = "Conversations"
    private static let fileExtension = "json"

    private(set) var conversations: [StoredConversation] = []
    @ObservationIgnored private let folderURL: URL
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    init() {
        folderURL = StorageConstants.applicationSupportURL.appending(path: Self.folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        conversations = loadAll()
    }

    func conversation(_ id: UUID) -> StoredConversation? {
        conversations.first { $0.id == id }
    }

    func list(profileID: UUID, matching query: String = "") -> [StoredConversation] {
        conversations.filter { $0.profileID == profileID && $0.matches(query) }
    }

    func save(_ conversation: StoredConversation) {
        guard let data = try? encoder.encode(conversation) else { return }
        try? data.write(to: fileURL(for: conversation.id), options: [.atomic, .completeFileProtection])
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        conversations.removeAll { $0.id == id }
    }

    func deleteAll() {
        conversations.map(\.id).forEach(delete)
    }

    private func fileURL(for id: UUID) -> URL {
        folderURL.appending(path: id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    private func loadAll() -> [StoredConversation] {
        let fileURLs = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        return fileURLs
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { try? decoder.decode(StoredConversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
