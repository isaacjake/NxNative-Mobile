
import Foundation

enum KeyManager {
    enum KeyError: LocalizedError {
        case invalidFile
        case storageFailed

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected keys file is not valid text."
            case .storageFailed:
                return "Could not securely save the keys file."
            }
        }
    }

    private static var keysDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("NxNative", isDirectory: true)
    }

    private static var keysURL: URL {
        keysDirectory.appendingPathComponent("prod.keys")
    }

    static var hasKeys: Bool {
        FileManager.default.fileExists(
            atPath: keysURL.path
        )
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

        guard let contents = String(
            data: data,
            encoding: .utf8
        ), !contents.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw KeyError.invalidFile
        }

        try FileManager.default.createDirectory(
            at: keysDirectory,
            withIntermediateDirectories: true
        )

        try data.write(
            to: keysURL,
            options: .atomic
        )

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: keysURL.path
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true

        var protectedURL = keysURL
        try protectedURL.setResourceValues(values)
    }

    static func loadKeys() throws -> Data {
        guard hasKeys else {
            throw KeyError.storageFailed
        }

        return try Data(contentsOf: keysURL)
    }

    static func deleteKeys() throws {
        if hasKeys {
            try FileManager.default.removeItem(at: keysURL)
        }
    }
}
