import Foundation
import Security

final class KeychainStore {
    private let service = "app.cargo.Cargo"
    private let account = "putio-access-token"
    private let chillAccount = "chill-user-token"
    private let tmdbAccount = "tmdb-api-key"
    private let openSubtitlesAccount = "opensubtitles-password"

    enum KeychainError: LocalizedError {
        case saveFailure(OSStatus)
        case deleteFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailure(let status):
                "Could not save the credential to Keychain (\(status))."
            case .deleteFailure(let status):
                "Could not remove the credential from Keychain (\(status))."
            }
        }
    }

    func readToken() -> String? { read(account: account) }
    func saveToken(_ token: String) throws { try save(token, account: account) }
    func deleteToken() throws { try delete(account: account) }

    func readChillToken() -> String? { read(account: chillAccount) }
    func saveChillToken(_ token: String) throws { try save(token, account: chillAccount) }
    func deleteChillToken() throws { try delete(account: chillAccount) }

    func readOpenSubtitlesPassword() -> String? { read(account: openSubtitlesAccount) }
    func saveOpenSubtitlesPassword(_ password: String) throws {
        if password.isEmpty { try delete(account: openSubtitlesAccount) } else { try save(password, account: openSubtitlesAccount) }
    }

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
