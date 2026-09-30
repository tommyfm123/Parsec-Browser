import Foundation

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(_ key: String) -> JSONValue? {
        guard case .object(let value) = self else { return nil }
        return value[key]
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

enum MCPTransport: String, Codable, CaseIterable, Identifiable {
    case http
    case stdio
    var id: String { rawValue }
    var title: String { self == .http ? "Remoto · URL" : "Local · Comando" }
}

struct MCPServer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var transport: MCPTransport
    var endpoint = ""
    var command = ""
    var arguments: [String] = []
    var isEnabled = true
    var detail: String { transport == .http ? endpoint : ([command] + arguments).joined(separator: " ") }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IntegrationError.invalid("Escribí un nombre para el MCP.") }
        guard transport == .http else {
            guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IntegrationError.invalid("Escribí el comando del servidor.") }
            return
        }
        guard let url = URL(string: endpoint), let host = url.host, url.user == nil, url.password == nil else { throw IntegrationError.invalid("Escribí una URL válida sin credenciales.") }
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard url.scheme == "https" || (url.scheme == "http" && isLocal) else { throw IntegrationError.invalid("Usá HTTPS; HTTP solo está permitido para localhost.") }
    }
}

struct MCPSecrets: Codable {
    var token = ""
    var environment: [String: String] = [:]
    var headers: [String: String] = [:]
}

struct MCPTool: Identifiable {
    let serverID: UUID
    let serverName: String
    let name: String
    let description: String
    let inputSchema: JSONValue
    let isReadOnly: Bool
    var id: String { serverID.uuidString + ":" + name }
    var modelDefinition: JSONValue {
        .object(["server": .string(serverID.uuidString), "application": .string(serverName), "tool": .string(name), "description": .string(description), "argumentsSchema": inputSchema])
    }
}

struct InstalledSkill: Codable, Identifiable {
    var id = UUID()
    let name: String
    let detail: String
    let instructions: String
    var isEnabled = true
}

enum MCPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(Int)
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "Sin conectar"
        case .connecting: "Conectando…"
        case .connected(let count): "Conectado · \(count) \(count == 1 ? "herramienta" : "herramientas")"
        case .failed(let message): message
        }
    }
}

enum IntegrationError: LocalizedError {
    case invalid(String)
    case disconnected
    case timeout
    case server(String)
    case keychain(Int32)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .server(let message): message
        case .disconnected: "El servidor MCP se desconectó. Volvé a conectarlo desde Configuración."
        case .timeout: "El MCP no respondió a tiempo. Revisá el servidor y su configuración."
        case .keychain: "No se pudieron guardar o leer las credenciales en el llavero de macOS."
        }
    }
}
