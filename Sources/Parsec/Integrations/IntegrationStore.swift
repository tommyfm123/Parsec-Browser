import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class IntegrationStore {
    static let shared = IntegrationStore()
    private struct Library: Codable {
        var servers: [MCPServer] = []
        var skills: [InstalledSkill] = []
    }
    private static let maximumSkillBytes = 256 * 1024
    private(set) var servers: [MCPServer] = []
    private(set) var skills: [InstalledSkill] = []
    private(set) var states: [UUID: MCPConnectionState] = [:]
    private(set) var tools: [UUID: [MCPTool]] = [:]
    var errorMessage: String?
    @ObservationIgnored private var clients: [UUID: MCPClient] = [:]
    @ObservationIgnored private var connectionIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var connectionTasks: [UUID: Task<[MCPTool], Error>] = [:]
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = StorageConstants.applicationSupportURL.appending(path: "integrations.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: fileURL))
            servers = library.servers
            skills = library.skills
        } catch { errorMessage = "No se pudo leer la biblioteca de integraciones. \(error.localizedDescription)" }
    }

    var hasEnabledServers: Bool { servers.contains(where: \.isEnabled) }
    var skillContext: String {
        skills.filter(\.isEnabled).map { "<installed-skill name=\"\($0.name)\">\n\($0.instructions)\n</installed-skill>" }.joined(separator: "\n\n")
    }

    func save(_ server: MCPServer, secrets: MCPSecrets) throws {
        try server.validate()
        var updated = servers
        if let index = updated.firstIndex(where: { $0.id == server.id }) { updated[index] = server }
        else { updated.append(server) }
        let previous = try IntegrationSecretStore.read(server.id)
        try IntegrationSecretStore.save(secrets, for: server.id)
        do { try persist(servers: updated, skills: skills) }
        catch {
            try IntegrationSecretStore.save(previous, for: server.id)
            throw error
        }
        disconnect(server.id)
        servers = updated
    }

    func removeServer(_ id: UUID) throws {
        let updated = servers.filter { $0.id != id }
        try persist(servers: updated, skills: skills)
        disconnect(id)
        servers = updated
        try IntegrationSecretStore.delete(id)
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        var updated = servers
        updated[index].isEnabled = enabled
        do {
            try persist(servers: updated, skills: skills)
            servers = updated
            if !enabled { disconnect(id) }
        } catch { errorMessage = error.localizedDescription }
    }

    func setSkillEnabled(_ id: UUID, enabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        var updated = skills
        updated[index].isEnabled = enabled
        do { try persist(servers: servers, skills: updated); skills = updated }
        catch { errorMessage = error.localizedDescription }
    }

    func removeSkill(_ id: UUID) {
        let updated = skills.filter { $0.id != id }
        do { try persist(servers: servers, skills: updated); skills = updated }
        catch { errorMessage = error.localizedDescription }
    }

    func connect(_ id: UUID) async throws -> [MCPTool] {
        guard let server = servers.first(where: { $0.id == id && $0.isEnabled }) else { throw IntegrationError.disconnected }
        if let existing = connectionTasks[id] { return try await existing.value }
        if case .connected = states[id], let tools = tools[id], clients[id] != nil { return tools }
        states[id] = .connecting
        let connectionID = UUID()
        connectionIDs[id] = connectionID
        let task = Task { [self] () throws -> [MCPTool] in
            let client = MCPClient(server: server, secrets: try IntegrationSecretStore.read(id))
            clients[id] = client
            client.onDisconnect = { [weak self] in
                guard let self, self.connectionIDs[id] == connectionID else { return }
                self.clients[id] = nil
                self.tools[id] = nil
                self.states[id] = .disconnected
            }
            do { return try await client.connect() }
            catch { client.close(); throw error }
        }
        connectionTasks[id] = task
        do {
            let discovered = try await task.value
            guard !task.isCancelled, connectionIDs[id] == connectionID, clients[id] != nil else { throw CancellationError() }
            connectionTasks[id] = nil
            tools[id] = discovered
            states[id] = .connected(discovered.count)
            return discovered
        } catch {
            guard connectionIDs[id] == connectionID else { throw error }
            connectionTasks[id] = nil
            clients.removeValue(forKey: id)?.close()
            tools[id] = nil
            states[id] = error is CancellationError ? .disconnected : .failed(error.localizedDescription)
            throw error
        }
    }

    func testConnection(_ id: UUID) async {
        disconnect(id)
        do { _ = try await connect(id) }
        catch { errorMessage = error.localizedDescription }
    }

    func availableTools() async -> [MCPTool] {
        var available: [MCPTool] = []
        for server in servers where server.isEnabled {
            if Task.isCancelled { break }
            do { available += try await connect(server.id) }
            catch { states[server.id] = .failed(error.localizedDescription) }
        }
        return available
    }

    func call(_ tool: MCPTool, arguments: JSONValue) async throws -> JSONValue {
        guard servers.contains(where: { $0.id == tool.serverID && $0.isEnabled }), let client = clients[tool.serverID],
              tools[tool.serverID]?.contains(where: { $0.name == tool.name }) == true else { throw IntegrationError.disconnected }
        guard case .object = arguments else { throw IntegrationError.invalid("Los argumentos del MCP deben ser un objeto JSON.") }
        do { return try await client.call(tool.name, arguments: arguments) }
        catch {
            disconnect(tool.serverID)
            states[tool.serverID] = .failed(error.localizedDescription)
            throw error
        }
    }

    func disconnect(_ id: UUID) {
        connectionIDs[id] = nil
        connectionTasks.removeValue(forKey: id)?.cancel()
        clients.removeValue(forKey: id)?.close()
        tools[id] = nil
        states[id] = .disconnected
    }

    func importMCPs(from url: URL) throws -> Int {
        let configuration = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .object(let definitions) = configuration["mcpServers"], !definitions.isEmpty else {
            throw IntegrationError.invalid("El JSON debe contener un objeto mcpServers con al menos un servidor.")
        }
        let imported = try definitions.sorted { $0.key < $1.key }.map { name, definition in
            let endpoint = definition["url"]?.string ?? ""
            var server = MCPServer(name: name, transport: endpoint.isEmpty ? .stdio : .http)
            server.endpoint = endpoint
            server.command = definition["command"]?.string ?? ""
            if let arguments = definition["args"] {
                guard let values = arguments.array, values.allSatisfy({ $0.string != nil }) else { throw IntegrationError.invalid("args debe ser una lista de textos.") }
                server.arguments = values.compactMap(\.string)
            }
            try server.validate()
            let secrets = MCPSecrets(environment: try stringDictionary(definition["env"]), headers: try stringDictionary(definition["headers"]))
            return (server, secrets)
        }
        guard !imported.contains(where: { candidate in servers.contains(where: { $0.name.caseInsensitiveCompare(candidate.0.name) == .orderedSame }) }) else {
            throw IntegrationError.invalid("Ya existe un MCP con uno de esos nombres. Editalo o cambiale el nombre en el JSON.")
        }
        var savedIDs: [UUID] = []
        do {
            for (server, secrets) in imported { try IntegrationSecretStore.save(secrets, for: server.id); savedIDs.append(server.id) }
            let updated = servers + imported.map(\.0)
            try persist(servers: updated, skills: skills)
            servers = updated
        } catch {
            for id in savedIDs { try IntegrationSecretStore.delete(id) }
            throw error
        }
        return imported.count
    }

    func importSkills(from url: URL) throws -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw IntegrationError.invalid("No se encontró el archivo o la carpeta.") }
        let files: [URL]
        if isDirectory.boolValue {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var found: [URL] = []
            while let candidate = enumerator?.nextObject() as? URL {
                if candidate.lastPathComponent == "SKILL.md" { found.append(candidate) }
                guard found.count <= 100 else { throw IntegrationError.invalid("Importá hasta 100 skills a la vez.") }
            }
            files = found.sorted { $0.path < $1.path }
        } else { files = [url] }
        guard !files.isEmpty else { throw IntegrationError.invalid("La carpeta debe contener archivos SKILL.md.") }
        let imported = try files.map { file in
            let data = try Data(contentsOf: file)
            guard data.count <= Self.maximumSkillBytes, let instructions = String(data: data, encoding: .utf8), !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw IntegrationError.invalid("Cada skill debe ser un Markdown UTF-8 de hasta 256 KB.")
            }
            let metadata = skillMetadata(instructions)
            let fallback = file.lastPathComponent == "SKILL.md" ? file.deletingLastPathComponent().lastPathComponent : file.deletingPathExtension().lastPathComponent
            return InstalledSkill(name: metadata["name"] ?? fallback, detail: metadata["description"] ?? "Skill importada", instructions: instructions)
        }
        let updated = skills + imported
        try persist(servers: servers, skills: updated)
        skills = updated
        return imported.count
    }

    private func stringDictionary(_ value: JSONValue?) throws -> [String: String] {
        guard let value else { return [:] }
        guard case .object(let dictionary) = value, dictionary.values.allSatisfy({ $0.string != nil }) else { throw IntegrationError.invalid("env y headers deben contener pares de texto.") }
        return dictionary.compactMapValues(\.string)
    }

    private func skillMetadata(_ instructions: String) -> [String: String] {
        let lines = instructions.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        var metadata: [String: String] = [:]
        for line in lines[1..<end] {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            metadata[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
        }
        return metadata
    }

    private func persist(servers: [MCPServer], skills: [InstalledSkill]) throws {
        let library = Library(servers: servers, skills: skills)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
