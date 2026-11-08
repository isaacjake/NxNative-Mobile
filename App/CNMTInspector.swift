import Foundation

struct CNMTInspection {
    let fileSize: Int
    let isRecognized: Bool
    let titleID: String?
    let version: UInt32?
    let contentType: UInt8?
    let contentCount: Int?
    let contentMetaCount: Int?
    let message: String
}

enum CNMTInspector {

    static func inspect(_ url: URL) -> CNMTInspection {
        do {
            let data = try Data(contentsOf: url)

            guard url.pathExtension.lowercased() == "cnmt" else {
                return failure(
                    data.count,
                    "This parser accepts plaintext .cnmt files only."
                )
            }

            guard data.count >= 0x20 else {
                return failure(
                    data.count,
                    "CNMT header is incomplete."
                )
            }

            let titleID = readUInt64(data, at: 0)
            let version = readUInt32(data, at: 8)
            let contentType = data[12]
            let extendedHeaderSize = Int(readUInt16(data, at: 14))
            let contentCount = Int(readUInt16(data, at: 16))
            let contentMetaCount = Int(readUInt16(data, at: 18))

            let contentBytes = contentCount.multipliedReportingOverflow(
                by: 0x38
            )

            let metaBytes = contentMetaCount.multipliedReportingOverflow(
                by: 0x10
            )

            guard !contentBytes.overflow,
                  !metaBytes.overflow else {
                return failure(
                    data.count,
                    "CNMT entry counts are invalid."
                )
            }

            let requiredSize =
                0x20 +
                extendedHeaderSize +
                contentBytes.partialValue +
                metaBytes.partialValue

            guard requiredSize <= data.count else {
                return failure(
                    data.count,
                    "CNMT entries extend beyond the available file."
                )
            }

            let formattedTitleID = String(
                format: "%016llX",
                titleID
            )

            return CNMTInspection(
                fileSize: data.count,
                isRecognized: true,
                titleID: formattedTitleID,
                version: version,
                contentType: contentType,
                contentCount: contentCount,
                contentMetaCount: contentMetaCount,
                message: "Plaintext CNMT header and entry ranges validated."
            )

        } catch {
            return failure(
                0,
                "Could not read CNMT file."
            )
        }
    }

    private static func failure(
        _ size: Int,
        _ message: String
    ) -> CNMTInspection {
        CNMTInspection(
            fileSize: size,
            isRecognized: false,
            titleID: nil,
            version: nil,
            contentType: nil,
            contentCount: nil,
            contentMetaCount: nil,
            message: message
        )
    }

    private static func readUInt16(
        _ data: Data,
        at offset: Int
    ) -> UInt16 {
        UInt16(data[offset]) |
        (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(
        _ data: Data,
        at offset: Int
    ) -> UInt32 {
        var value: UInt32 = 0

        for index in 0..<4 {
            value |= UInt32(data[offset + index]) << (index * 8)
        }

        return value
    }

    private static func readUInt64(
        _ data: Data,
        at offset: Int
    ) -> UInt64 {
        var value: UInt64 = 0

        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (index * 8)
        }

        return value
    }
}
