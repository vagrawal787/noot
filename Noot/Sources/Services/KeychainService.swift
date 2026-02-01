import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.noot.calendar"

    private init() {}

    // MARK: - Refresh Token Storage

    func saveRefreshToken(_ token: String, for email: String) throws {
        let account = "refresh_token:\(email)"

        // Delete existing token first
        try? deleteRefreshToken(for: email)

        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getRefreshToken(for email: String) throws -> String? {
        let account = "refresh_token:\(email)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return token
    }

    func deleteRefreshToken(for email: String) throws {
        let account = "refresh_token:\(email)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Access Token Cache (short-lived, also in Keychain for security)

    func saveAccessToken(_ token: String, expiry: Date, for email: String) throws {
        let account = "access_token:\(email)"

        // Delete existing token first
        try? deleteAccessToken(for: email)

        // Store token and expiry together as JSON
        let tokenInfo = AccessTokenInfo(token: token, expiry: expiry)
        let encoder = JSONEncoder()
        let tokenData = try encoder.encode(tokenInfo)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getAccessToken(for email: String) throws -> (token: String, expiry: Date)? {
        let account = "access_token:\(email)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.decodingFailed
        }

        let decoder = JSONDecoder()
        let tokenInfo = try decoder.decode(AccessTokenInfo.self, from: data)

        return (tokenInfo.token, tokenInfo.expiry)
    }

    func deleteAccessToken(for email: String) throws {
        let account = "access_token:\(email)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Delete All Tokens for Account

    func deleteAllTokens(for email: String) throws {
        try deleteRefreshToken(for: email)
        try deleteAccessToken(for: email)
    }
}

// MARK: - Supporting Types

private struct AccessTokenInfo: Codable {
    let token: String
    let expiry: Date
}

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain storage"
        case .decodingFailed:
            return "Failed to decode data from Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .readFailed(let status):
            return "Failed to read from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
