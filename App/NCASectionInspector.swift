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
            return failure("The section is too small for a PFS0 header.")
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            try handle.seek(toOffset: section.offsetBytes)

            let header = try readExactly(handle, count: 16)

            guard header.prefix(4) == Data("PFS0".utf8) else {
                return failure(
                    "No PFS0 signature was found at the start of this section."
                )
            }

            let count = Int(readUInt32(header, at: 4))
            let stringTableSize = Int(readUInt32(header, at: 8))

            guard count > 0, count <= 100_000 else {
                return failure("The PFS0 entry count is invalid.")
            }

            guard stringTableSize > 0,
                  stringTableSize <= 64 * 1024 * 1024 else {
                return failure("The PFS0 string table size is invalid.")
            }

            let entryBytes = count.multipliedReportingOverflow(
                by: 0x18
            )

            guard !entryBytes.overflow else {
                return failure("The PFS0 entry table is too large.")
            }

            let metadataSize = UInt64(16)
                + UInt64(entryBytes.partialValue)
                + UInt64(stringTableSize)

            guard metadataSize <= section.sizeBytes else {
                return failure(
                    "The PFS0 metadata extends beyond the section."
                )
            }

            let rawEntries = try readExactly(
                handle,
                count: entryBytes.partialValue
            )

            let stringTable = try readExactly(
                handle,
                count: stringTableSize
            )

            let dataAreaSize = section.sizeBytes - metadataSize

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

                guard nameOffset >= 0,
                      nameOffset < stringTable.count else {
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
                message: "PFS0 directory metadata validated. File contents were not read or decrypted.",
                entries: results
            )

        } catch {
            return failure(
                "Could not inspect the section: \(error.localizedDescription)"
            )
        }
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
            "The section ended before all directory metadata could be read."
        }
    }
}
