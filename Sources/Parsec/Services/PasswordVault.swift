import Foundation
import LocalAuthentication
import Security

struct SavedCredential: Hashable, Identifiable {
    let host: String
    let account: String
    var id: String { host + "|" + account }

    func matches(host pageHost: String) -> Bool {
        let normalizedHost = PasswordVault.normalized(pageHost)
        return normalizedHost == PasswordVault.normalized(host)
    }
}

enum PasswordVaultError: Error {
    case authenticationFailed
    case unsafePage
    case notFound
    case keychain(OSStatus)
}

final class PasswordVault {
    static let shared = PasswordVault()
    private static let authenticationReason = "rellenar tu contraseña"
    private static let urlColumnNames: Set<String> = ["url", "website", "login_uri"]
    private static let usernameColumnNames: Set<String> = ["username", "login_username", "user"]
    private static let passwordColumnNames: Set<String> = ["password", "login_password"]
    private static let creatorCode: OSType = 0x5052_5343

    static func normalized(_ host: String) -> String {
        host.lowercased()
    }

    func allCredentials() -> [SavedCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: Self.creatorCode,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String else { return nil }
            return SavedCredential(host: host, account: item[kSecAttrAccount as String] as? String ?? "")
        }
        .sorted { ($0.host, $0.account) < ($1.host, $1.account) }
    }

    func credentials(forHost host: String) -> [SavedCredential] {
        credentials(exactHost: Self.normalized(host))
    }

    private func credentials(exactHost host: String) -> [SavedCredential] {
        var query = baseQuery(host: host)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            (item[kSecAttrAccount as String] as? String).map { SavedCredential(host: host, account: $0) }
        }
    }

    func hasPassword(host: String, account: String, password: String) -> Bool {
        (try? readPassword(for: SavedCredential(host: Self.normalized(host), account: account))) == password
    }

    func authenticatedPassword(for credential: SavedCredential) async throws -> String {
        let context = LAContext()
        let isAuthenticated = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: Self.authenticationReason)) ?? false
        guard isAuthenticated else { throw PasswordVaultError.authenticationFailed }
        return try readPassword(for: credential)
    }

    func save(host rawHost: String, account: String, password: String) throws {
        let host = Self.normalized(rawHost)
        let passwordData = Data(password.utf8)
        var query = baseQuery(host: host)
        query[kSecAttrAccount as String] = account
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: passwordData] as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            if updateStatus != errSecSuccess { throw PasswordVaultError.keychain(updateStatus) }
            return
        }
        query[kSecValueData as String] = passwordData
        query[kSecAttrLabel as String] = StorageConstants.keychainLabelPrefix + host
        query[kSecAttrCreator as String] = Self.creatorCode
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PasswordVaultError.keychain(addStatus) }
    }

    func delete(_ credential: SavedCredential) {
        var query = baseQuery(host: credential.host)
        query[kSecAttrAccount as String] = credential.account
        SecItemDelete(query as CFDictionary)
    }

    func importCSV(at fileURL: URL) throws -> Int {
        let rows = CSVParser.rows(from: try String(contentsOf: fileURL, encoding: .utf8))
        guard let header = rows.first?.map({ $0.lowercased() }),
              let urlIndex = header.firstIndex(where: Self.urlColumnNames.contains),
              let usernameIndex = header.firstIndex(where: Self.usernameColumnNames.contains),
              let passwordIndex = header.firstIndex(where: Self.passwordColumnNames.contains) else { return 0 }
        var importedCount = 0
        for row in rows.dropFirst() where row.count > max(urlIndex, usernameIndex, passwordIndex) {
            let host = URL(string: row[urlIndex])?.host() ?? ""
            let password = row[passwordIndex]
            guard !host.isEmpty, !password.isEmpty else { continue }
            try save(host: host, account: row[usernameIndex], password: password)
            importedCount += 1
        }
        return importedCount
    }

    private func readPassword(for credential: SavedCredential) throws -> String {
        var query = baseQuery(host: credential.host)
        query[kSecAttrAccount as String] = credential.account
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw status == errSecItemNotFound ? PasswordVaultError.notFound : PasswordVaultError.keychain(status)
        }
        return password
    }

    private func baseQuery(host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrCreator as String: Self.creatorCode,
        ]
    }
}

enum CSVParser {
    private static let quote: Character = "\""
    private static let separator: Character = ","

    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        var characters = text.makeIterator()
        var pending = characters.next()
        while let character = pending {
            pending = characters.next()
            switch (character, isInsideQuotes) {
            case (quote, true) where pending == quote:
                currentField.append(quote)
                pending = characters.next()
            case (quote, _):
                isInsideQuotes.toggle()
            case (separator, false):
                currentRow.append(currentField)
                currentField = ""
            case (_, false) where character.isNewline:
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            default:
                currentField.append(character)
            }
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }
}
