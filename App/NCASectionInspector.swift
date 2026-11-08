import Foundation

struct NCASectionFileEntry: Identifiable {
    let id: Int
    let name: String
    let offset: UInt64
    let size: UInt64
}

struct NCASectionInspection {
    let isRecognized: Bool
    let message: String
    let entries: [NCASectionFileEntry]
}

enum NCASectionInspector {

    private static let maximumScanSize = 64 * 1024 * 1024

    static func inspectUnencryptedPartitionFS(
        _ url: URL,
        section: NCASectionInfo
    ) -> NCASectionInspection {

        guard section.isValid else {
            return failure("The section range is invalid.")
        }

        guard section.fsType == 1 else {
            return failure("This section is not identified as PartitionFS.")
        }

        guard section.encryptionType == 1 else {
            return failure(
                "This section is encrypted. The inspector only reads unencrypted sections."
            )
        }

        guard section.sizeBytes >= 16 else {
            return failure("The section is too small to inspect.")
        }

        guard section.sizeBytes <= UInt64(maximumScanSize) else {
            return failure(
                "The section exceeds the 64 MB diagnostic scan limit."
            )
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            try handle.seek(toOffset: section.offsetBytes)

            let sectionData = try readExactly(
                handle,
                count: Int(section.sizeBytes)
            )

            let signature = Data("PFS0".utf8)

            guard sectionData.count >= 4 else {
                return failure("The section data is incomplete.")
            }

            var foundSignature = false
            var lastError = "No valid PFS0 directory was found."

            for position in 0...(sectionData.count - 4) {

                let candidate = sectionData.subdata(
                    in: position..<(position + 4)
                )

                guard candidate == signature else {
                    continue
                }

                foundSignature = true

                let result = inspectPFS0(
                    sectionData,
                    at: position
                )

                if result.isRecognized {
                    return result
                }

                lastError = result.message
            }

            if !foundSignature {
                return failure(
                    "No PFS0 signature was found anywhere in this section. The section may contain hash-layer metadata or another structure."
                )
            }

            return failure(
                "A PFS0 signature was found, but its directory metadata did not validate. \(lastError)"
            )

        } catch {
            return failure(
                "Could not inspect the section: \(error.localizedDescription)"
            )
        }
    }

    private static func inspectPFS0(
        _ data: Data,
        at position: Int
    ) -> NCASectionInspection {

        guard position >= 0,
              position <= data.count - 16 else {
            return failure("The PFS0 header is incomplete.")
        }

        let countValue = readUInt32(data, at: position + 4)
        let stringSizeValue = readUInt32(data, at: position + 8)

        guard countValue > 0,
              countValue <= 100_000 else {
            return failure("The PFS0 entry count is invalid.")
        }

        guard stringSizeValue > 0,
              stringSizeValue <= 64 * 1024 * 1024 else {
            return failure("The PFS0 string table size is invalid.")
        }

        let count = Int(countValue)
        let stringTableSize = Int(stringSizeValue)

        let entryBytes = count.multipliedReportingOverflow(
            by: 0x18
        )

        guard !entryBytes.overflow else {
            return failure("The PFS0 entry table is too large.")
        }

        let metadataSize = 16
            .addingReportingOverflow(entryBytes.partialValue)

        guard !metadataSize.overflow else {
            return failure("The PFS0 metadata size is invalid.")
        }

        let completeMetadataSize =
            metadataSize.partialValue.addingReportingOverflow(
                stringTableSize
            )

        guard !completeMetadataSize.overflow else {
            return failure("The PFS0 metadata size is invalid.")
        }

        let metadataEnd = position.addingReportingOverflow(
            completeMetadataSize.partialValue
        )

        guard !metadataEnd.overflow,
              metadataEnd.partialValue <= data.count else {
            return failure(
                "The PFS0 metadata extends beyond the section."
            )
        }

        let entriesStart = position + 16

        let rawEntries = data.subdata(
            in: entriesStart..<(entriesStart + entryBytes.partialValue)
        )

        let stringsStart = entriesStart + entryBytes.partialValue

        let stringTable = data.subdata(
            in: stringsStart..<(stringsStart + stringTableSize)
        )

        let dataAreaSize = UInt64(
            data.count - metadataEnd.partialValue
        )

        var results: [NCASectionFileEntry] = []

        for index in 0..<count {

            let base = index * 0x18

            let offset = readUInt64(
                rawEntries,
                at: base
            )

            let size = readUInt64(
                rawEntries,
                at: base + 8
            )

            let nameOffset = Int(
                readUInt32(rawEntries, at: base + 16)
            )

            guard nameOffset < stringTable.count else {
                return failure("A filename offset is invalid.")
            }

            guard offset <= dataAreaSize,
                  size <= dataAreaSize - offset else {
                return failure(
                    "A file entry extends beyond the section."
                )
            }

            guard let terminator = stringTable[
                nameOffset...
            ].firstIndex(of: 0) else {
                return failure("A filename is not terminated.")
            }

            let nameData = Data(
                stringTable[nameOffset..<terminator]
            )

            guard let name = String(
                data: nameData,
                encoding: .utf8
            ), !name.isEmpty else {
                return failure("A filename is invalid.")
            }

            results.append(
                NCASectionFileEntry(
                    id: index,
                    name: name,
                    offset: offset,
                    size: size
                )
            )
        }

        return NCASectionInspection(
            isRecognized: true,
            message: "PFS0 directory metadata validated at section offset \(position). File contents were not read or decrypted.",
            entries: results
        )
    }

    private static func failure(
        _ message: String
    ) -> NCASectionInspection {
        NCASectionInspection(
            isRecognized: false,
            message: message,
            entries: []
        )
    }

    private static func readExactly(
        _ handle: FileHandle,
        count: Int
    ) throws -> Data {

        var result = Data()

        while result.count < count {

            let chunk = try handle.read(
                upToCount: count - result.count
            ) ?? Data()

            guard !chunk.isEmpty else {
                throw InspectionError.truncatedData
            }

            result.append(chunk)
        }

        return result
    }

    private static func readUInt32(
        _ data: Data,
        at offset: Int
    ) -> UInt32 {

        guard offset >= 0,
              offset + 4 <= data.count else {
            return 0
        }

        var value: UInt32 = 0

        for index in 0..<4 {
            value |= UInt32(data[offset + index])
                << (index * 8)
        }

        return value
    }

    private static func readUInt64(
        _ data: Data,
        at offset: Int
    ) -> UInt64 {

        guard offset >= 0,
              offset + 8 <= data.count else {
            return 0
        }

        var value: UInt64 = 0

        for index in 0..<8 {
            value |= UInt64(data[offset + index])
                << (index * 8)
        }

        return value
    }

    private enum InspectionError: LocalizedError {
        case truncatedData

        var errorDescription: String? {
            "The section ended before all requested bytes could be read."
        }
    }
}
