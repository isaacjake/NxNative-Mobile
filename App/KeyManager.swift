import Foundation
import Security
enum KeyManager {
    enum KeyError: LocalizedError {
        case invalidFile
        case saveFailed
        case notFound
        case readFailed
        case missingHeaderKey
        case invalidHeaderKey
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
            case .missingHeaderKey:
                return "No NCA header key was found in prod.keys."
            case .invalidHeaderKey:
                return "The NCA header key must contain exactly 64 hexadecimal characters."
            }
        }
    }
    private static let service = "com.nxnative.mobile"
    private static let account = "prod.keys"
    static var hasKeys: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
            == errSecSuccess
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
    static func loadHeaderKey() throws -> Data {
        let data = try loadKeys()
        guard let text = String(data: data, encoding: .utf8) else {
            throw KeyError.invalidFile
        }
        var foundValue: String?
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard parts.count == 2 else {
                continue
            }
            let name = parts[0]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if name == "nca_header_key" || name == "header_key" {
                foundValue = String(parts[1])
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let value = foundValue else {
            throw KeyError.missingHeaderKey
        }
        let cleaned = value.replacingOccurrences(
            of: " ",
            with: ""
        )
        guard cleaned.count == 64,
              cleaned.allSatisfy({
                  $0.isHexDigit
              }) else {
            throw KeyError.invalidHeaderKey
        }
        var bytes = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(
                cleaned[index..<nextIndex],
                radix: 16
            ) else {
                throw KeyError.invalidHeaderKey
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
    static func deleteKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess ||
              status == errSecItemNotFound else {
            throw KeyError.readFailed
        }
    }
}
