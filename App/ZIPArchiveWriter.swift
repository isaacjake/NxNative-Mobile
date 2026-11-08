import Foundation

struct ZIPArchiveItem {
    let sourceURL: URL
    let archivePath: String
}

enum ZIPArchiveError: LocalizedError {
    case noFiles
    case tooManyFiles
    case fileTooLarge(String)
    case filenameTooLong(String)
    case archiveTooLarge
    case cannotCreateArchive

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "No files were selected for the ZIP archive."
        case .tooManyFiles:
            return "The ZIP archive contains too many files."
        case .fileTooLarge(let name):
            return "\(name) is too large for this ZIP format."
        case .filenameTooLong(let name):
            return "The filename is too long: \(name)"
        case .archiveTooLarge:
            return "The ZIP archive exceeds the supported size."
        case .cannotCreateArchive:
            return "The ZIP archive could not be created."
        }
    }
}

enum ZIPArchiveWriter {

    private static let maximumZIP32Size: UInt64 = UInt64(UInt32.max)

    static func create(items: [ZIPArchiveItem]) throws -> URL {
        guard !items.isEmpty else {
            throw ZIPArchiveError.noFiles
        }

        guard items.count <= Int(UInt16.max) else {
            throw ZIPArchiveError.tooManyFiles
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "NxNative-Saved-Files-\(UUID().uuidString.prefix(8)).zip"
            )

        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil
        ) else {
            throw ZIPArchiveError.cannotCreateArchive
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer {
                try? output.close()
            }

            var centralDirectory = Data()
            var currentOffset: UInt64 = 0

            for item in items {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: item.sourceURL.path
                )

                let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

                guard fileSize <= maximumZIP32Size else {
                    throw ZIPArchiveError.fileTooLarge(
                        item.sourceURL.lastPathComponent
                    )
                }

                let archiveName = item.archivePath
                    .replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                let filenameData = Data(archiveName.utf8)

                guard !filenameData.isEmpty,
                      filenameData.count <= Int(UInt16.max) else {
                    throw ZIPArchiveError.filenameTooLong(archiveName)
                }

                guard currentOffset <= maximumZIP32Size else {
                    throw ZIPArchiveError.archiveTooLarge
                }

                let checksum = try crc32(of: item.sourceURL)

                let modifiedDate =
                    attributes[.modificationDate] as? Date ?? Date()

                let (dosTime, dosDate) = dosDateTime(modifiedDate)

                let localHeader = makeLocalHeader(
                    filename: filenameData,
                    checksum: checksum,
                    fileSize: UInt32(fileSize),
                    dosTime: dosTime,
                    dosDate: dosDate
                )

                let localHeaderOffset = UInt32(currentOffset)

                try output.write(contentsOf: localHeader)
                currentOffset += UInt64(localHeader.count)

                try copyFile(
                    from: item.sourceURL,
                    to: output,
                    expectedSize: fileSize
                )

                currentOffset += fileSize

                guard currentOffset <= maximumZIP32Size else {
                    throw ZIPArchiveError.archiveTooLarge
                }

                let centralHeader = makeCentralHeader(
                    filename: filenameData,
                    checksum: checksum,
                    fileSize: UInt32(fileSize),
                    dosTime: dosTime,
                    dosDate: dosDate,
                    localHeaderOffset: localHeaderOffset
                )

                centralDirectory.append(centralHeader)
            }

            guard currentOffset <= maximumZIP32Size,
                  UInt64(centralDirectory.count) <= maximumZIP32Size else {
                throw ZIPArchiveError.archiveTooLarge
            }

            let centralDirectoryOffset = UInt32(currentOffset)
            let centralDirectorySize = UInt32(centralDirectory.count)

            try output.write(contentsOf: centralDirectory)
            currentOffset += UInt64(centralDirectory.count)

            guard currentOffset <= maximumZIP32Size else {
                throw ZIPArchiveError.archiveTooLarge
            }

            let endRecord = makeEndRecord(
                fileCount: UInt16(items.count),
                centralDirectorySize: centralDirectorySize,
                centralDirectoryOffset: centralDirectoryOffset
            )

            try output.write(contentsOf: endRecord)
            try output.synchronize()

            return outputURL

        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func copyFile(
        from sourceURL: URL,
        to destination: FileHandle,
        expectedSize: UInt64
    ) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? input.close()
        }

        var copied: UInt64 = 0

        while let chunk = try input.read(upToCount: 256 * 1024),
              !chunk.isEmpty {
            copied += UInt64(chunk.count)

            guard copied <= expectedSize else {
                throw ZIPArchiveError.archiveTooLarge
            }

            try destination.write(contentsOf: chunk)
        }

        guard copied == expectedSize else {
            throw ZIPArchiveError.cannotCreateArchive
        }
    }

    private static func crc32(of url: URL) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: url)
        defer {
            try? input.close()
        }

        var checksum: UInt32 = 0xFFFFFFFF

        while let chunk = try input.read(upToCount: 256 * 1024),
              !chunk.isEmpty {
            for byte in chunk {
                let index = Int((checksum ^ UInt32(byte)) & 0xFF)
                checksum = (checksum >> 8) ^ crcTable[index]
            }
        }

        return checksum ^ 0xFFFFFFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { value in
            var result = UInt32(value)

            for _ in 0..<8 {
                if (result & 1) != 0 {
                    result = (result >> 1) ^ 0xEDB88320
                } else {
                    result >>= 1
                }
            }

            return result
        }
    }()

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        let year = min(2107, max(1980, components.year ?? 1980))
        let month = min(12, max(1, components.month ?? 1))
        let day = min(31, max(1, components.day ?? 1))
        let hour = min(23, max(0, components.hour ?? 0))
        let minute = min(59, max(0, components.minute ?? 0))
        let second = min(59, max(0, components.second ?? 0))

        let time = UInt16(
            (hour << 11) |
            (minute << 5) |
            (second / 2)
        )

        let dosDate = UInt16(
            ((year - 1980) << 9) |
            (month << 5) |
            day
        )

        return (time, dosDate)
    }

    private static func makeLocalHeader(
        filename: Data,
        checksum: UInt32,
        fileSize: UInt32,
        dosTime: UInt16,
        dosDate: UInt16
    ) -> Data {
        var data = Data()

        append(UInt32(0x04034B50), to: &data)
        append(UInt16(20), to: &data)
        append(UInt16(0x0800), to: &data)
        append(UInt16(0), to: &data)
        append(dosTime, to: &data)
        append(dosDate, to: &data)
        append(checksum, to: &data)
        append(fileSize, to: &data)
        append(fileSize, to: &data)
        append(UInt16(filename.count), to: &data)
        append(UInt16(0), to: &data)

        data.append(filename)

        return data
    }

    private static func makeCentralHeader(
        filename: Data,
        checksum: UInt32,
        fileSize: UInt32,
        dosTime: UInt16,
        dosDate: UInt16,
        localHeaderOffset: UInt32
    ) -> Data {
        var data = Data()

        append(UInt32(0x02014B50), to: &data)
        append(UInt16(20), to: &data)
        append(UInt16(20), to: &data)
        append(UInt16(0x0800), to: &data)
        append(UInt16(0), to: &data)
        append(dosTime, to: &data)
        append(dosDate, to: &data)
        append(checksum, to: &data)
        append(fileSize, to: &data)
        append(fileSize, to: &data)
        append(UInt16(filename.count), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(0), to: &data)
        append(localHeaderOffset, to: &data)

        data.append(filename)

        return data
    }

    private static func makeEndRecord(
        fileCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) -> Data {
        var data = Data()

        append(UInt32(0x06054B50), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(fileCount, to: &data)
        append(fileCount, to: &data)
        append(centralDirectorySize, to: &data)
        append(centralDirectoryOffset, to: &data)
        append(UInt16(0), to: &data)

        return data
    }

    private static func append(
        _ value: UInt16,
        to data: inout Data
    ) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func append(
        _ value: UInt32,
        to data: inout Data
    ) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
