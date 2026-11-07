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
        case noValidTitleKeys

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected keys file is not valid UTF-8 text."
            case .saveFailed:
                return "Could not save keys securely."
            case .notFound:
                return "No saved keys were found."
            case .readFailed:
                return "Could not read saved keys."
            case .missingHeaderKey:
                return "NCA header key was not found."
            case .invalidHeaderKey:
                return "NCA header key must contain 64 hexadecimal characters."
            case .noValidTitleKeys:
                return "No valid title-key entries were found."
            }
        }
    }

    private static let service = "com.nxnative.mobile"
    private static let account = "prod.keys"
    private static let titleAccount = "title.keys"

    static var hasKeys: Bool {
        itemExists(account: account)
    }

    static var hasTitleKeys: Bool {
        itemExists(account: titleAccount)
    }

    static func importKeys(from sourceURL: URL) throws {
        let data = try readFile(sourceURL)

        guard String(data: data, encoding: .utf8) != nil else {
            throw KeyError.invalidFile
        }

        try save(data, account: account)
    }

    static func importTitleKeys(from sourceURL: URL) throws {
        let data = try readFile(sourceURL)

        guard
            let text = String(data: data, encoding: .utf8),
            validTitleKeyCount(in: text) > 0
        else {
            throw KeyError.noValidTitleKeys
        }

        try save(data, account: titleAccount)
    }

    static func loadKeys() throws -> Data {
        try load(account: account)
    }

    static func loadTitleKeys() throws -> Data {
        try load(account: titleAccount)
    }

    static func loadHeaderKey() throws -> Data {
        let data = try loadKeys()

        guard let text = String(data: data, encoding: .utf8) else {
            throw KeyError.invalidFile
        }

        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(
                separator: "=",
                maxSplits: 1
            )

            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()

            if name == "nca_header_key" || name == "header_key" {
                let value = parts[1].trimmingCharacters(
                    .whitespacesAndNewlines
                )

                guard let bytes = hexData(value), bytes.count == 32 else {
                    throw KeyError.invalidHeaderKey
                }

                return bytes
            }
        }

        throw KeyError.missingHeaderKey
    }

    static func hasTitleKey(forRightsID rightsID: String) -> Bool {
        guard
            rightsID.count == 32,
            let data = try? loadTitleKeys(),
            let text = String(data: data, encoding: .utf8)
        else {
            return false
        }

        let target = rightsID.uppercased()

        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(
                separator: "=",
                maxSplits: 1
            )

            guard parts.count == 2 else { continue }

            let identifier = parts[0].trimmingCharacters(
                in: .whitespacesAndNewlines
            ).uppercased()

            let key = parts[1].trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if identifier == target,
               let keyData = hexData(key),
               keyData.count == 16 {
                return true
            }
        }

        return false
    }

    static func deleteKeys() throws {
        try delete(account: account)
    }

    static func deleteTitleKeys() throws {
        try delete(account: titleAccount)
    }

    private static func validTitleKeyCount(in text: String) -> Int {
        text.components(separatedBy: .newlines).reduce(0) { count, line in
            let parts = line.split(separator: "=", maxSplits: 1)

            guard parts.count == 2 else { return count }

            let identifier = parts[0].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let key = parts[1].trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard
                identifier.count == 32,
                hexData(identifier) != nil,
                let keyData = hexData(key),
                keyData.count == 16
            else {
                return count
            }

            return count + 1
        }
    }

    private static func hexData(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }

        var result = Data()
        var index = value.startIndex

        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)

            guard let byte = UInt8(value[index..<next], radix: 16) else {
                return nil
            }

            result.append(byte)
            index = next
        }

        return result
    }

    private static func readFile(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: url)
    }

    private static func itemExists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw KeyError.saveFailed
        }
    }

    private static func load(account: String) throws -> Data {
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

        guard status == errSecSuccess else {
            throw status == errSecItemNotFound
                ? KeyError.notFound
                : KeyError.readFailed
        }

        guard let data = result as? Data else {
            throw KeyError.readFailed
        }

        return data
    }

    private static func delete(account: String) throws {
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
