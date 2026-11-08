import Foundation
import SwiftUI

struct NCASectionFileEntry: Identifiable {
    let id: Int
    let name: String
    let offset: UInt64
    let size: UInt64
    let fileOffset: UInt64
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
            return failure("This section is encrypted. Only unencrypted sections can be inspected.")
        }

        guard section.sizeBytes >= 16,
              section.sizeBytes <= UInt64(maximumScanSize) else {
            return failure("The section size is outside the diagnostic scan limit.")
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
            var foundSignature = false
            var lastError = "No valid PFS0 directory was found."

            for position in 0...(sectionData.count - 4) {
                guard sectionData.subdata(
                    in: position..<(position + 4)
                ) == signature else {
                    continue
                }

                foundSignature = true

                let result = inspectPFS0(
                    sectionData,
                    at: position,
                    sectionFileOffset: section.offsetBytes
                )

                if result.isRecognized {
                    return result
                }

                lastError = result.message
            }

            if !foundSignature {
                return failure("No PFS0 signature was found in this section.")
            }

            return failure("PFS0 metadata did not validate. \(lastError)")

        } catch {
            return failure("Could not inspect the section: \(error.localizedDescription)")
        }
    }

    static func extractUnencryptedEntry(
        _ entry: NCASectionFileEntry,
        from sourceURL: URL,
        to directory: URL
    ) throws -> URL {

        guard entry.size <= UInt64(maximumScanSize) else {
            throw ExtractionError.fileTooLarge
        }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: sourceURL.path
        )

        let sourceSize =
            (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        guard entry.fileOffset <= sourceSize,
              entry.size <= sourceSize - entry.fileOffset else {
            throw ExtractionError.invalidRange
        }

        let safeName = URL(
            fileURLWithPath: entry.name.replacingOccurrences(
                of: "\\",
                with: "_"
            )
        ).lastPathComponent

        guard !safeName.isEmpty,
              safeName != ".",
              safeName != ".." else {
            throw ExtractionError.unsafeFilename
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
            throw ExtractionError.outputCreationFailed
        }

        do {
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: destination)

            defer {
                try? input.close()
                try? output.close()
            }

            try input.seek(toOffset: entry.fileOffset)

            var remaining = entry.size

            while remaining > 0 {
                let amount = Int(
                    min(remaining, UInt64(256 * 1024))
                )

                let chunk = try input.read(
                    upToCount: amount
                ) ?? Data()

                guard !chunk.isEmpty else {
                    throw ExtractionError.truncatedData
                }

                try output.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
            }

            try output.synchronize()
            return destination

        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func inspectPFS0(
        _ data: Data,
        at position: Int,
        sectionFileOffset: UInt64
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

        let entryBytes = count.multipliedReportingOverflow(by: 0x18)

        guard !entryBytes.overflow else {
            return failure("The PFS0 entry table is too large.")
        }

        let metadataSize = 16.addingReportingOverflow(
            entryBytes.partialValue
        )

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
            return failure("PFS0 metadata extends beyond the section.")
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

        let absoluteDataStart =
            sectionFileOffset.addingReportingOverflow(
                UInt64(metadataEnd.partialValue)
            )

        guard !absoluteDataStart.overflow else {
            return failure("The PFS0 data offset overflowed.")
        }

        var results: [NCASectionFileEntry] = []

        for index in 0..<count {
            let base = index * 0x18

            let offset = readUInt64(rawEntries, at: base)
            let size = readUInt64(rawEntries, at: base + 8)

            let nameOffset = Int(
                readUInt32(rawEntries, at: base + 16)
            )

            guard nameOffset < stringTable.count else {
                return failure("A filename offset is invalid.")
            }

            guard offset <= dataAreaSize,
                  size <= dataAreaSize - offset else {
                return failure("A file entry extends beyond the section.")
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

            let absoluteFileOffset =
                absoluteDataStart.partialValue.addingReportingOverflow(
                    offset
                )

            guard !absoluteFileOffset.overflow else {
                return failure("A file data offset overflowed.")
            }

            results.append(
                NCASectionFileEntry(
                    id: index,
                    name: name,
                    offset: offset,
                    size: size,
                    fileOffset: absoluteFileOffset.partialValue
                )
            )
        }

        return NCASectionInspection(
            isRecognized: true,
            message: "PFS0 directory metadata validated. File data offsets calculated; file contents have not yet been extracted.",
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
            value |= UInt32(data[offset + index]) << (index * 8)
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
            value |= UInt64(data[offset + index]) << (index * 8)
        }

        return value
    }

    private enum InspectionError: LocalizedError {
        case truncatedData

        var errorDescription: String? {
            "The section ended before all requested bytes could be read."
        }
    }

    private enum ExtractionError: LocalizedError {
        case fileTooLarge
        case invalidRange
        case unsafeFilename
        case outputCreationFailed
        case truncatedData

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "The file exceeds the 64 MB extraction limit."
            case .invalidRange:
                return "The file data range is outside the saved NCA."
            case .unsafeFilename:
                return "The entry has an unsafe filename."
            case .outputCreationFailed:
                return "Could not create the extracted file."
            case .truncatedData:
                return "The saved NCA ended before the complete file could be copied."
            }
        }
    }
}

struct NCASectionFileExportView: View {
    let entry: NCASectionFileEntry
    let sourceURL: URL
    let gameID: UUID

    @State private var isExporting = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                exportFile()
            } label: {
                if isExporting {
                    Label("Saving...", systemImage: "hourglass")
                } else {
                    Label("Save Unencrypted File", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExporting)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(
                        statusMessage.hasPrefix("Saved") ? .green : .orange
                    )
            }
        }
    }

    private func exportFile() {
        guard !isExporting else {
            return
        }

        isExporting = true
        statusMessage = nil

        DispatchQueue.global(qos: .utility).async {
            do {
                let documents = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0]

                let outputFolder = documents
                    .appendingPathComponent(
                        "NxNativeSectionFiles",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        gameID.uuidString,
                        isDirectory: true
                    )

                let savedURL = try NCASectionInspector.extractUnencryptedEntry(
                    entry,
                    from: sourceURL,
                    to: outputFolder
                )

                DispatchQueue.main.async {
                    statusMessage = "Saved: \(savedURL.lastPathComponent)"
                    isExporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Save failed: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }
}
