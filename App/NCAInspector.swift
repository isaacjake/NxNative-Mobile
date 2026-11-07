
import Foundation
import CommonCrypto

struct NCASectionInfo {
    let index: Int
    let startMediaUnit: UInt32
    let endMediaUnit: UInt32
    let offsetBytes: UInt64
    let sizeBytes: UInt64
    let isValid: Bool
    let fsType: UInt8
    let hashType: UInt8
    let encryptionType: UInt8
}

struct NCAInspection {
    let isRecognized: Bool
    let magic: String
    let distributionType: UInt8?
    let contentType: UInt8?
    let keyGenerationOld: UInt8?
    let keyAreaEncryptionKeyIndex: UInt8?
    let keyGeneration: UInt8?
    let rightsIDPresent: Bool?
    let fileSize: UInt64
    let message: String
    let sections: [NCASectionInfo]

    // Compatibility with older GamesView code.
    var cryptoType: UInt8? { nil }
}

enum NCAInspector {
    private static let sectionTableOffset = 0x240
    private static let sectionEntrySize = 0x10
    private static let fsHeaderOffset = 0x400
    private static let fsHeaderSize = 0x200
    private static let mediaUnitSize: UInt64 = 0x200

    static func inspect(_ url: URL) -> NCAInspection {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let fileSize =
                (attributes[.size] as? NSNumber)?.uint64Value ?? 0

            guard fileSize >= 0xC00 else {
                return failure(
                    fileSize,
                    "File is too small for a complete NCA header."
                )
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let encryptedData = try handle.read(upToCount: 0xC00),
                  encryptedData.count == 0xC00 else {
                return failure(
                    fileSize,
                    "Could not read the complete NCA header."
                )
            }

            let headerKey = try KeyManager.loadHeaderKey()

            guard headerKey.count == 32 else {
                return failure(
                    fileSize,
                    "The NCA header key must be 32 bytes."
                )
            }

            var header = Array(encryptedData)
            let key = Array(headerKey)

            for sector in 0...1 {
                try NCAHeaderXTS.decryptSector(
                    &header,
                    key: key,
                    sectorIndex: UInt64(sector)
                )
            }

            let magic = magicString(header, at: 0x200)

            guard magic == "NCA3" ||
                  magic == "NCA2" ||
                  magic == "NCA0" else {
                return failure(
                    fileSize,
                    "No supported NCA signature found after header decryption. Check the key and file."
                )
            }

            guard magic == "NCA3" else {
                return NCAInspection(
                    isRecognized: true,
                    magic: magic,
                    distributionType: nil,
                    contentType: nil,
                    keyGenerationOld: nil,
                    keyAreaEncryptionKeyIndex: nil,
                    keyGeneration: nil,
                    rightsIDPresent: nil,
                    fileSize: fileSize,
                    message: "Older NCA format detected. Additional format handling is needed.",
                    sections: []
                )
            }

            for sector in 2...5 {
                try NCAHeaderXTS.decryptSector(
                    &header,
                    key: key,
                    sectorIndex: UInt64(sector)
                )
            }

            let sections = inspectSections(
                header: header,
                fileSize: fileSize
            )

            let rightsIDPresent = hasRightsID(header)

            return NCAInspection(
                isRecognized: true,
                magic: magic,
                distributionType: header[0x204],
                contentType: header[0x205],
                keyGenerationOld: header[0x206],
                keyAreaEncryptionKeyIndex: header[0x207],
                keyGeneration: header[0x220],
                rightsIDPresent: rightsIDPresent,
                fileSize: fileSize,
                message: "NCA3 header decrypted. Header fields, Rights ID presence, and section ranges inspected. Section contents are not decrypted.",
                sections: sections
            )

        } catch {
            return failure(
                0,
                error.localizedDescription
            )
        }
    }

    private static func hasRightsID(
        _ header: [UInt8]
    ) -> Bool {
        let start = 0x230
        let end = start + 16

        guard header.count >= end else {
            return false
        }

        return header[start..<end].contains {
            $0 != 0
        }
    }

    private static func inspectSections(
        header: [UInt8],
        fileSize: UInt64
    ) -> [NCASectionInfo] {
        var sections: [NCASectionInfo] = []

        for index in 0..<4 {
            let tableOffset =
                sectionTableOffset + index * sectionEntrySize

            let start = readUInt32(header, at: tableOffset)
            let end = readUInt32(header, at: tableOffset + 4)

            let offset = UInt64(start) * mediaUnitSize
            let endOffset = UInt64(end) * mediaUnitSize

            let valid =
                end > start &&
                endOffset <= fileSize

            let size = end >= start
                ? endOffset - offset
                : 0

            let fsOffset =
                fsHeaderOffset + index * fsHeaderSize

            sections.append(
                NCASectionInfo(
                    index: index,
                    startMediaUnit: start,
                    endMediaUnit: end,
                    offsetBytes: offset,
                    sizeBytes: size,
                    isValid: valid,
                    fsType: readUInt8(header, at: fsOffset + 0x02),
                    hashType: readUInt8(header, at: fsOffset + 0x03),
                    encryptionType: readUInt8(header, at: fsOffset + 0x04)
                )
            )
        }

        return sections
    }

    private static func readUInt8(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt8 {
        guard offset >= 0 && offset < bytes.count else {
            return 0
        }

        return bytes[offset]
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt32 {
        guard offset >= 0 && offset + 4 <= bytes.count else {
            return 0
        }

        var value: UInt32 = 0

        for index in 0..<4 {
            value |= UInt32(bytes[offset + index]) << (index * 8)
        }

        return value
    }

    private static func magicString(
        _ bytes: [UInt8],
        at offset: Int
    ) -> String {
        guard offset >= 0 && offset + 4 <= bytes.count else {
            return "Unknown"
        }

        return String(
            bytes: bytes[offset..<offset + 4],
            encoding: .ascii
        ) ?? "Unknown"
    }

    private static func failure(
        _ fileSize: UInt64,
        _ message: String
    ) -> NCAInspection {
        NCAInspection(
            isRecognized: false,
            magic: "Unknown",
            distributionType: nil,
            contentType: nil,
            keyGenerationOld: nil,
            keyAreaEncryptionKeyIndex: nil,
            keyGeneration: nil,
            rightsIDPresent: nil,
            fileSize: fileSize,
            message: message,
            sections: []
        )
    }
}

private enum NCAHeaderXTS {
    static func decryptSector(
        _ data: inout [UInt8],
        key: [UInt8],
        sectorIndex: UInt64
    ) throws {
        let sectorSize = 0x200
        let sectorOffset = Int(sectorIndex) * sectorSize

        guard key.count == 32,
              sectorOffset + sectorSize <= data.count else {
            throw XTSFailure.invalidInput
        }

        let dataKey = Array(key[0..<16])
        let tweakKey = Array(key[16..<32])

        var tweakInput = [UInt8](repeating: 0, count: 16)

        for index in 0..<8 {
            tweakInput[15 - index] =
                UInt8((sectorIndex >> (index * 8)) & 0xFF)
        }

        var tweak = try aesBlock(
            tweakInput,
            key: tweakKey,
            operation: CCOperation(kCCEncrypt)
        )

        for blockOffset in stride(
            from: 0,
            to: sectorSize,
            by: 16
        ) {
            let absoluteOffset = sectorOffset + blockOffset
            var block = [UInt8](repeating: 0, count: 16)

            for index in 0..<16 {
                block[index] =
                    data[absoluteOffset + index] ^ tweak[index]
            }

            let decrypted = try aesBlock(
                block,
                key: dataKey,
                operation: CCOperation(kCCDecrypt)
            )

            for index in 0..<16 {
                data[absoluteOffset + index] =
                    decrypted[index] ^ tweak[index]
            }

            multiplyTweak(&tweak)
        }
    }

    private static func aesBlock(
        _ input: [UInt8],
        key: [UInt8],
        operation: CCOperation
    ) throws -> [UInt8] {
        guard input.count == 16, key.count == 16 else {
            throw XTSFailure.invalidInput
        }

        var output = [UInt8](repeating: 0, count: 16)
        let outputCount = output.count
        var moved: size_t = 0

        let status = key.withUnsafeBytes { keyBuffer in
            input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        inputBuffer.baseAddress,
                        input.count,
                        outputBuffer.baseAddress,
                        outputCount,
                        &moved
                    )
                }
            }
        }

        guard status == kCCSuccess, moved == 16 else {
            throw XTSFailure.cryptographicOperationFailed
        }

        return output
    }

    private static func multiplyTweak(
        _ tweak: inout [UInt8]
    ) {
        var carry: UInt8 = 0

        for index in 0..<16 {
            let nextCarry = tweak[index] >> 7
            tweak[index] = (tweak[index] << 1) | carry
            carry = nextCarry
        }

        if carry != 0 {
            tweak[0] ^= 0x87
        }
    }

    private enum XTSFailure: LocalizedError {
        case invalidInput
        case cryptographicOperationFailed

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Invalid AES-XTS input or sector length."
            case .cryptographicOperationFailed:
                return "The AES operation failed."
            }
        }
    }
}
