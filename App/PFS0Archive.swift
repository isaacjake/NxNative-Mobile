
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
    case unsafeFilename
    case outputCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid PFS0 header."
        case .invalidEntryCount: return "Invalid number of archive entries."
        case .invalidStringTable: return "Invalid archive string table."
        case .invalidFilename: return "Invalid archive filename."
        case .truncatedArchive: return "The archive is incomplete or truncated."
        case .invalidOffset: return "An entry points outside the archive."
        case .unsafeFilename: return "The entry has an unsafe filename."
        case .outputCreationFailed: return "Could not create the extracted file."
        }
    }
}

struct PFS0Archive {
    let entries: [PFS0Entry]
    private let archiveURL: URL
    private let dataOffset: UInt64

    static func open(_ url: URL) throws -> PFS0Archive {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

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

        let tableSize = count.multipliedReportingOverflow(by: 0x18)
        guard !tableSize.overflow else {
            throw PFS0Error.invalidEntryCount
        }

        let metadataSize = UInt64(16)
            + UInt64(tableSize.partialValue)
            + UInt64(stringTableSize)

        guard metadataSize <= fileSize else {
            throw PFS0Error.truncatedArchive
        }

        let rawEntries = try readExactly(
            handle,
            count: tableSize.partialValue
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
            let nameOffset = Int(readUInt32(rawEntries, at: base + 16))

            guard nameOffset < stringTable.count else {
                throw PFS0Error.invalidFilename
            }

            guard offset <= fileSize - metadataSize,
                  size <= fileSize - metadataSize - offset else {
                throw PFS0Error.invalidOffset
            }

            guard let terminator = stringTable[nameOffset...]
                .firstIndex(of: 0) else {
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

        return PFS0Archive(
            entries: results,
            archiveURL: url,
            dataOffset: metadataSize
        )
    }

    func extract(
        _ entry: PFS0Entry,
        to directory: URL,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> URL {

        guard entries.contains(where: {
            $0.id == entry.id &&
            $0.offset == entry.offset &&
            $0.size == entry.size
        }) else {
            throw PFS0Error.invalidOffset
        }

        let safeName = URL(
            fileURLWithPath: entry.name
                .replacingOccurrences(of: "\\", with: "_")
        ).lastPathComponent

        guard !safeName.isEmpty,
              safeName != ".",
              safeName != ".." else {
            throw PFS0Error.unsafeFilename
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(
            "\(entry.id)-\(safeName)"
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: nil
        ) else {
            throw PFS0Error.outputCreationFailed
        }

        do {
            let input = try FileHandle(forReadingFrom: archiveURL)
            let output = try FileHandle(forWritingTo: destination)

            defer {
                try? input.close()
                try? output.close()
            }

            let start = dataOffset.addingReportingOverflow(entry.offset)
            guard !start.overflow else {
                throw PFS0Error.invalidOffset
            }

            try input.seek(toOffset: start.partialValue)

            var remaining = entry.size
            var copied: UInt64 = 0
            let bufferSize = 256 * 1024
            let progressInterval: UInt64 = 32 * 1024 * 1024
            var nextProgress: UInt64 = progressInterval

            progress?(0, entry.size)

            while remaining > 0 {
                let amount = Int(
                    min(remaining, UInt64(bufferSize))
                )

                guard let chunk = try input.read(upToCount: amount),
                      !chunk.isEmpty else {
                    throw PFS0Error.truncatedArchive
                }

                try output.write(contentsOf: chunk)

                let chunkSize = UInt64(chunk.count)
                remaining -= chunkSize
                copied += chunkSize

                if copied >= nextProgress || remaining == 0 {
                    progress?(copied, entry.size)
                    nextProgress = copied + progressInterval
                }
            }

            try output.synchronize()
            return destination

        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
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
