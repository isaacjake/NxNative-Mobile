
import Foundation
import Security

enum KeyManager {
    enum KeyError: LocalizedError {
        case invalidFile
        case saveFailed
        case notFound
        case readFailed

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected keys file is not valid UTF-8 text."
            case .saveFailed:
                return "Could not securely save the keys."
            case .notFound:
                return "No keys have been imported."
            case .readFailed:
                return "Could not read the saved keys."
            }
        }
    }

    private static let service = "com.nxnative.mobile"
    private static let account = "prod.keys"

    static var hasKeys: Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]

        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func importKeys(from sourceURL: URL) throws {
        let hasAccess =
            sourceURL.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)

        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            throw KeyError.invalidFile
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw KeyError.saveFailed
        }
    }

    static func loadKeys() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?

        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeyError.notFound
        }

        return data
    }

    static func deleteKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError.readFailed
        }
    }
}
