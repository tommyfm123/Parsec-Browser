import Foundation

final class MCPRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class MCPClient {
    private static let protocolVersion = "2025-11-25"
    private static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    private static let maximumMessageBytes = 4 * 1024 * 1024
    private static let requestTimeout: Duration = .seconds(30)
    let server: MCPServer
    var onDisconnect: (() -> Void)?
    private let secrets: MCPSecrets
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pendingData = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var nextID = 0
    private var sessionID: String?
    private var negotiatedVersion = MCPClient.protocolVersion
    private var isClosed = false
    private let session: URLSession

    init(server: MCPServer, secrets: MCPSecrets) {
        self.server = server
        self.secrets = secrets
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: MCPRedirectPolicy(), delegateQueue: nil)
    }

    func connect() async throws -> [MCPTool] {
        try server.validate()
        if server.transport == .stdio { try launch() }
        let result = try await request("initialize", parameters: .object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Parsec"), "version": .string("1.0")])
        ]))
        guard let version = result["protocolVersion"]?.string, Self.supportedVersions.contains(version) else {
            throw IntegrationError.server("Este MCP usa una versión de protocolo no compatible.")
        }
        negotiatedVersion = version
        try await notify("notifications/initialized")
        guard result["capabilities"]?["tools"] != nil else { return [] }
        var tools: [MCPTool] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            try Task.checkCancellation()
            let parameters = cursor.map { JSONValue.object(["cursor": .string($0)]) } ?? .object([:])
            let page = try await request("tools/list", parameters: parameters)
            guard let definitions = page["tools"]?.array else { throw IntegrationError.server("El MCP devolvió una lista de herramientas inválida.") }
            tools += try definitions.map { definition in
                guard let name = definition["name"]?.string, !name.isEmpty, let schema = definition["inputSchema"] else {
                    throw IntegrationError.server("El MCP devolvió una herramienta inválida.")
                }
                return MCPTool(serverID: server.id, serverName: server.name, name: name, description: definition["description"]?.string ?? "", inputSchema: schema, isReadOnly: definition["annotations"]?["readOnlyHint"] == .bool(true))
            }
            cursor = page["nextCursor"]?.string
            if let cursor, !seenCursors.insert(cursor).inserted { throw IntegrationError.server("El MCP repitió una página de herramientas.") }
            guard tools.count <= 1000 else { throw IntegrationError.server("El MCP excedió el límite de herramientas.") }
        } while cursor != nil
        return tools
    }

    func call(_ tool: String, arguments: JSONValue) async throws -> JSONValue {
        try await request("tools/call", parameters: .object(["name": .string(tool), "arguments": arguments]))
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        output?.readabilityHandler = nil
        input?.closeFile()
        if let process, process.isRunning { process.terminate() }
        session.invalidateAndCancel()
        onDisconnect?()
        for identifier in Array(pending.keys) { resolve(identifier, result: .failure(IntegrationError.disconnected)) }
    }

    private func launch() throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let usesAbsolutePath = server.command.hasPrefix("/")
        let executableURL = URL(fileURLWithPath: usesAbsolutePath ? server.command : "/usr/bin/env")
        process.executableURL = executableURL
        process.arguments = usesAbsolutePath ? server.arguments : [server.command] + server.arguments
        var environment = CommandLineTool.environment(for: executableURL)
        environment.merge(secrets.environment) { _, configured in configured }
        process.environment = environment
        process.currentDirectoryURL = AssistantWorkspace.folderURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.close() } }
        self.process = process
        do { try process.run() }
        catch { close(); throw IntegrationError.server("No se pudo iniciar el comando del MCP. Revisá que esté instalado y sea ejecutable.") }
    }

    private func request(_ method: String, parameters: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        guard !isClosed else { throw IntegrationError.disconnected }
        nextID += 1
        let identifier = nextID
        let message = JSONValue.object(["jsonrpc": .string("2.0"), "id": .number(Double(identifier)), "method": .string(method), "params": parameters])
        if server.transport == .http {
            guard let response = try await sendHTTP(message, identifier: identifier) else { throw IntegrationError.server("El MCP no devolvió una respuesta.") }
            return try decodeResult(response)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[identifier] = continuation
                deadlines[identifier] = Task { [weak self] in
                    do { try await Task.sleep(for: Self.requestTimeout) }
                    catch { return }
                    self?.resolve(identifier, result: .failure(IntegrationError.timeout))
                }
                do { try write(message) }
                catch { resolve(identifier, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(identifier, result: .failure(CancellationError())) }
        }
    }

    private func notify(_ method: String) async throws {
        let message = JSONValue.object(["jsonrpc": .string("2.0"), "method": .string(method)])
        if server.transport == .http { _ = try await sendHTTP(message, identifier: nil) }
        else { try write(message) }
    }

    private func write(_ message: JSONValue) throws {
        guard let input, !isClosed else { throw IntegrationError.disconnected }
        var data = try JSONEncoder().encode(message)
        data.append(UInt8(ascii: "\n"))
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return close() }
        pendingData.append(data)
        guard pendingData.count <= Self.maximumMessageBytes else { return close() }
        while let newline = pendingData.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(pendingData[..<newline])
            pendingData.removeSubrange(...newline)
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: line) else { return close() }
            if message["method"] != nil {
                rejectServerRequest(message)
                continue
            }
            guard case .number(let numericID) = message["id"], let identifier = Int(exactly: numericID) else { continue }
            resolve(identifier, result: Result { try decodeResult(message) })
        }
    }

    private func rejectServerRequest(_ message: JSONValue) {
        guard let identifier = message["id"] else { return }
        let response = JSONValue.object(["jsonrpc": .string("2.0"), "id": identifier, "error": .object(["code": .number(-32601), "message": .string("Client capability not supported")])])
        do { try write(response) }
        catch { close() }
    }

    private func resolve(_ identifier: Int, result: Result<JSONValue, Error>) {
        deadlines.removeValue(forKey: identifier)?.cancel()
        pending.removeValue(forKey: identifier)?.resume(with: result)
    }

    private func decodeResult(_ message: JSONValue) throws -> JSONValue {
        if message["error"] != nil { throw IntegrationError.server("El MCP rechazó la solicitud. Revisá los permisos y los parámetros de la herramienta.") }
        guard let result = message["result"] else { throw IntegrationError.server("Respuesta MCP inválida.") }
        return result
    }

    private func sendHTTP(_ message: JSONValue, identifier: Int?) async throws -> JSONValue? {
        guard let endpoint = URL(string: server.endpoint), !isClosed else { throw IntegrationError.disconnected }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (header, value) in secrets.headers { request.setValue(value, forHTTPHeaderField: header) }
        if !secrets.token.isEmpty { request.setValue("Bearer \(secrets.token)", forHTTPHeaderField: "Authorization") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "MCP-Session-Id") }
        if message["method"] != .string("initialize") { request.setValue(negotiatedVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        request.httpBody = try JSONEncoder().encode(message)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw IntegrationError.server("Respuesta HTTP inválida.") }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 { throw IntegrationError.server("El MCP necesita autorización. Agregá un token válido en Editar.") }
            if response.statusCode == 404, sessionID != nil { close(); throw IntegrationError.disconnected }
            throw IntegrationError.server("El MCP respondió HTTP \(response.statusCode). Revisá la URL y la compatibilidad con Streamable HTTP.")
        }
        if let assignedID = response.value(forHTTPHeaderField: "MCP-Session-Id") { sessionID = assignedID }
        guard let identifier else { return nil }
        if response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            var eventData: [String] = []
            var lineBytes = Data()
            var receivedBytes = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                receivedBytes += 1
                guard receivedBytes <= Self.maximumMessageBytes else { throw IntegrationError.server("La respuesta MCP es demasiado grande.") }
                guard byte == UInt8(ascii: "\n") else { lineBytes.append(byte); continue }
                let line = String(decoding: lineBytes, as: UTF8.self).trimmingCharacters(in: .newlines)
                lineBytes.removeAll(keepingCapacity: true)
                if line.hasPrefix("data:") { eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
                guard line.isEmpty, !eventData.isEmpty else { continue }
                let payload = eventData.joined(separator: "\n")
                eventData.removeAll()
                guard !payload.isEmpty else { continue }
                if let result = try matchingResponse(Data(payload.utf8), identifier: identifier) { return result }
            }
            throw IntegrationError.disconnected
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            guard data.count <= Self.maximumMessageBytes else { throw IntegrationError.server("La respuesta MCP es demasiado grande.") }
        }
        guard let result = try matchingResponse(data, identifier: identifier) else { throw IntegrationError.server("El MCP devolvió un identificador de respuesta inválido.") }
        return result
    }

    private func matchingResponse(_ data: Data, identifier: Int) throws -> JSONValue? {
        let message = try JSONDecoder().decode(JSONValue.self, from: data)
        guard message["id"] == .number(Double(identifier)), message["method"] == nil else { return nil }
        return message
    }
}
