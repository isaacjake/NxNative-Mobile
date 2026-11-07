
import Foundation

struct PFS0Entry: Identifiable {
    let id: Int
    let name: String
    let offset: UInt64
    let size: UInt64
}

enum PFS0Error: LocalizedError {
    case invalidHeader
    case invalidEntryCount
    case invalidStringTable
    case invalidFilename
    case truncatedArchive
    case invalidOffset

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "This file does not contain a valid PFS0 header."
        case .invalidEntryCount:
            return "The archive contains an invalid number of entries."
        case .invalidStringTable:
            return "The archive string table is invalid."
        case .invalidFilename:
            return "An archive entry has an invalid filename."
        case .truncatedArchive:
            return "The archive is incomplete or truncated."
        case .invalidOffset:
            return "An archive entry points outside the archive."
        }
    }
}

struct PFS0Archive {
    let entries: [PFS0Entry]

    static func open(_ url: URL) throws -> PFS0Archive {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()

        guard fileSize >= 16 else {
            throw PFS0Error.truncatedArchive
        }

        try handle.seek(toOffset: 0)

        let header = try readExactly(handle, count: 16)

        guard header.prefix(4) == Data("PFS0".utf8) else {
            throw PFS0Error.invalidHeader
        }

        let count = Int(readUInt32(header, at: 4))
        let stringTableSize = Int(readUInt32(header, at: 8))

        guard count > 0, count <= 100_000 else {
            throw PFS0Error.invalidEntryCount
        }

        guard stringTableSize > 0,
              stringTableSize <= 64 * 1024 * 1024 else {
            throw PFS0Error.invalidStringTable
        }

        let entryTableSize = count.multipliedReportingOverflow(by: 0x18)

        guard !entryTableSize.overflow else {
            throw PFS0Error.invalidEntryCount
        }

        let metadataSize = UInt64(16)
            + UInt64(entryTableSize.partialValue)
            + UInt64(stringTableSize)

        guard metadataSize <= fileSize else {
            throw PFS0Error.truncatedArchive
        }

        let rawEntries = try readExactly(
            handle,
            count: entryTableSize.partialValue
        )

        let stringTable = try readExactly(
            handle,
            count: stringTableSize
        )

        var results: [PFS0Entry] = []

        for index in 0..<count {
            let base = index * 0x18

            let offset = readUInt64(rawEntries, at: base)
            let size = readUInt64(rawEntries, at: base + 8)
            let nameOffset = Int(
                readUInt32(rawEntries, at: base + 16)
            )

            guard nameOffset >= 0,
                  nameOffset < stringTable.count else {
                throw PFS0Error.invalidFilename
            }

            guard offset <= fileSize - metadataSize,
                  size <= fileSize - metadataSize - offset else {
                throw PFS0Error.invalidOffset
            }

            let nameBytes = stringTable[nameOffset...]

            guard let terminator = nameBytes.firstIndex(of: 0) else {
                throw PFS0Error.invalidFilename
            }

            let filenameData = Data(
                stringTable[nameOffset..<terminator]
            )

            guard let filename = String(
                data: filenameData,
                encoding: .utf8
            ), !filename.isEmpty else {
                throw PFS0Error.invalidFilename
            }

            results.append(
                PFS0Entry(
                    id: index,
                    name: filename,
                    offset: offset,
                    size: size
                )
            )
        }

        return PFS0Archive(entries: results)
    }

    private static func readExactly(
        _ handle: FileHandle,
        count: Int
    ) throws -> Data {
        guard count >= 0 else {
            throw PFS0Error.truncatedArchive
        }

        var result = Data()

        while result.count < count {
            let remaining = count - result.count
            let chunk = try handle.read(upToCount: remaining) ?? Data()

            guard !chunk.isEmpty else {
                throw PFS0Error.truncatedArchive
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
