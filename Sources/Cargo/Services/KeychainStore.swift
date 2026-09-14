import Foundation
import Security

final class KeychainStore {
    private let service = "app.cargo.Cargo"
    private let account = "putio-access-token"
    private let tmdbAccount = "tmdb-api-key"

    enum KeychainError: LocalizedError {
        case saveFailure(OSStatus)
        case deleteFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailure(let status):
                "Could not save the Put.io token to Keychain (\(status))."
            case .deleteFailure(let status):
                "Could not remove the Put.io token from Keychain (\(status))."
            }
        }
    }

    func readToken() -> String? { read(account: account) }
    func saveToken(_ token: String) throws { try save(token, account: account) }
    func deleteToken() throws { try delete(account: account) }

    func readTMDBKey() -> String? { read(account: tmdbAccount) }
    func saveTMDBKey(_ key: String) throws {
        if key.isEmpty { try delete(account: tmdbAccount) } else { try save(key, account: tmdbAccount) }
    }

    private func read(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailure(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailure(updateStatus)
        }
    }

    private func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailure(status)
        }
    }
}
