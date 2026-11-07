
import Foundation
import CommonCrypto

struct NCAInspection {
    let isRecognized: Bool
    let magic: String
    let contentType: UInt8?
    let cryptoType: UInt8?
    let keyGeneration: UInt8?
    let fileSize: UInt64
    let message: String
}

enum NCAInspector {

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

            let encryptedData = try handle.read(upToCount: 0xC00)

            guard let encryptedData,
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

            // NCA headers use 512-byte AES-XTS sectors.
            // First decrypt sectors 0 and 1.
            try NCAHeaderXTS.decryptSector(
                &header,
                key: key,
                sectorIndex: 0
            )

            try NCAHeaderXTS.decryptSector(
                &header,
                key: key,
                sectorIndex: 1
            )

            let firstMagic = magicString(header, at: 0x200)

            guard firstMagic == "NCA3" ||
                  firstMagic == "NCA2" ||
                  firstMagic == "NCA0" else {
                return result(
                    false,
                    "Unknown",
                    nil,
                    nil,
                    nil,
                    fileSize,
                    "Header decryption completed, but no supported NCA signature was found. Check the key and file."
                )
            }

            // NCA3 uses sectors 2 through 5 for its
            // four filesystem headers.
            if firstMagic == "NCA3" {
                for sector in 2...5 {
                    try NCAHeaderXTS.decryptSector(
                        &header,
                        key: key,
                        sectorIndex: UInt64(sector)
                    )
                }
            } else {
                return result(
                    false,
                    firstMagic,
                    nil,
                    nil,
                    nil,
                    fileSize,
                    "An older NCA format was detected. Additional format-specific handling is needed."
                )
            }

            return result(
                true,
                firstMagic,
                header[0x205],
                header[0x206],
                header[0x207],
                fileSize,
                "NCA3 header successfully decrypted and recognized."
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
            message: message
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

        // Nintendo stores the sector number in
        // big-endian form in the 16-byte tweak.
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

        var output = [UInt8](repeating: 0, count: 16)
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
                        output.count,
                        &moved
                    )
                }
            }
        }

        guard status == kCCSuccess,
              moved == 16 else {
            throw XTSFailure.cryptographicOperationFailed
        }

        return output
    }

    // XTS multiplication by alpha in GF(2^128).
    private static func multiplyTweak(
        _ tweak: inout [UInt8]
    ) {
        var carry: UInt8 = 0

        for index in 0..<16 {
            let nextCarry = tweak[index] >> 7

            tweak[index] =
                (tweak[index] << 1) | carry

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
