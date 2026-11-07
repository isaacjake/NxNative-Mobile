
import Foundation
import CommonCrypto

struct NCASectionInfo {
    let index: Int
    let startMediaUnit: UInt32
    let endMediaUnit: UInt32
    let offsetBytes: UInt64
    let sizeBytes: UInt64

    var isPresent: Bool {
        startMediaUnit != 0 || endMediaUnit != 0
    }
}

struct NCAInspection {
    let isRecognized: Bool
    let magic: String
    let contentType: UInt8?
    let cryptoType: UInt8?
    let keyGeneration: UInt8?
    let fileSize: UInt64
    let message: String
    let sections: [NCASectionInfo]
}

enum NCAInspector {

    private static let sectionTableOffset = 0x240
    private static let sectionEntrySize = 0x10
    private static let mediaUnitSize: UInt64 = 0x200

    static func inspect(_ url: URL) -> NCAInspection {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )

            let fileSize =
                (attributes[.size] as? NSNumber)?.uint64Value ?? 0

            guard fileSize >= 0xC00 else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize,
                    "File is too small for a complete NCA header."
                )
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let encryptedData = try handle.read(upToCount: 0xC00),
                  encryptedData.count == 0xC00 else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize,
                    "Could not read the complete NCA header."
                )
            }

            let headerKey = try KeyManager.loadHeaderKey()

            guard headerKey.count == 32 else {
                return result(
                    false, "Unknown", nil, nil, nil,
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

            let firstMagic = magicString(header, at: 0x200)

            guard firstMagic == "NCA3" ||
                  firstMagic == "NCA2" ||
                  firstMagic == "NCA0" else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize,
                    "No supported NCA signature found after header decryption. Check the key and file."
                )
            }

            guard firstMagic == "NCA3" else {
                return result(
                    false, firstMagic, nil, nil, nil,
                    fileSize,
                    "An older NCA format was detected. Additional format handling is needed."
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

            return NCAInspection(
                isRecognized: true,
                magic: firstMagic,
                contentType: header[0x205],
                cryptoType: header[0x206],
                keyGeneration: header[0x207],
                fileSize: fileSize,
                message: "NCA3 header successfully decrypted and recognized. Section table inspected.",
                sections: sections
            )

        } catch {
            return result(
                false,
                "Error",
                nil,
                nil,
                nil,
                0,
                error.localizedDescription
            )
        }
    }

    private static func inspectSections(
        header: [UInt8],
        fileSize: UInt64
    ) -> [NCASectionInfo] {

        var sections: [NCASectionInfo] = []

        for index in 0..<4 {
            let base = sectionTableOffset +
                index * sectionEntrySize

            let start = readUInt32(header, at: base)
            let end = readUInt32(header, at: base + 4)

            let startBytes =
                UInt64(start).multipliedReportingOverflow(
                    by: mediaUnitSize
                )

            let endBytes =
                UInt64(end).multipliedReportingOverflow(
                    by: mediaUnitSize
                )

            guard !startBytes.overflow,
                  !endBytes.overflow else {
                continue
            }

            let offset = startBytes.partialValue
            let endOffset = endBytes.partialValue

            guard endOffset >= offset,
                  endOffset <= fileSize else {
                continue
            }

            sections.append(
                NCASectionInfo(
                    index: index,
                    startMediaUnit: start,
                    endMediaUnit: end,
                    offsetBytes: offset,
                    sizeBytes: endOffset - offset
                )
            )
        }

        return sections
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt32 {
        guard offset + 4 <= bytes.count else {
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
        guard offset + 4 <= bytes.count else {
            return "Unknown"
        }

        return String(
            bytes: bytes[offset..<offset + 4],
            encoding: .ascii
        ) ?? "Unknown"
    }

    private static func result(
        _ recognized: Bool,
        _ magic: String,
        _ contentType: UInt8?,
        _ cryptoType: UInt8?,
        _ keyGeneration: UInt8?,
        _ fileSize: UInt64,
        _ message: String
    ) -> NCAInspection {
        NCAInspection(
            isRecognized: recognized,
            magic: magic,
            contentType: contentType,
            cryptoType: cryptoType,
            keyGeneration: keyGeneration,
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

        guard input.count == 16,
              key.count == 16 else {
            throw XTSFailure.invalidInput
        }

        let inputCount = input.count
        let keyCount = key.count
        let outputCount = 16

        var output = [UInt8](
            repeating: 0,
            count: outputCount
        )

        var moved: size_t = 0

        let status = key.withUnsafeBytes { keyBuffer in
            input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        keyCount,
                        nil,
                        inputBuffer.baseAddress,
                        inputCount,
                        outputBuffer.baseAddress,
                        outputCount,
                        &moved
                    )
                }
            }
        }

        guard status == kCCSuccess,
              moved == outputCount else {
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
