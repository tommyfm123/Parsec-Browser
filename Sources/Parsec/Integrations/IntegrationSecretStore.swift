import Foundation
import Security

enum IntegrationSecretStore {
    private static let service = "dev.tommy.parsec.mcp"

    static func read(_ id: UUID) throws -> MCPSecrets {
        var query = query(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return MCPSecrets() }
        guard status == errSecSuccess, let data = result as? Data else { throw IntegrationError.keychain(status) }
        return try JSONDecoder().decode(MCPSecrets.self, from: data)
    }

    static func save(_ secrets: MCPSecrets, for id: UUID) throws {
        let data = try JSONEncoder().encode(secrets)
        let query = query(for: id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw IntegrationError.keychain(status) }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else { throw IntegrationError.keychain(insertionStatus) }
    }

    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IntegrationError.keychain(status) }
    }

    private static func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
}
