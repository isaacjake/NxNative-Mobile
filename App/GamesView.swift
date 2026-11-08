import SwiftUI
struct GamesView: View {
    let games: [ImportedGame]
    let importAction: () -> Void
    let deleteAction: (ImportedGame) -> Void
    @State private var inspectionResults: [UUID: GameFileInspection] = [:]
    @State private var archiveResults: [UUID: [PFS0Entry]] = [:]
    @State private var archiveErrors: [UUID: String] = [:]
    @State private var extractionMessages: [String: String] = [:]
    @State private var extractingEntries: Set<String> = []
    @State private var ncaResults: [String: NCAInspection] = [:]
    @State private var extractionProgress: [String: Double] = [:]
    @State private var extractionBytes: [String: UInt64] = [:]
    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No Games Imported", systemImage: "gamecontroller")
                    } description: {
                        Text("Import a legally obtained NSP or XCI game file to get started.")
                    } actions: {
                        Button(action: importAction) {
                            Text("Import Game")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(games) { game in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.title2)
                                        .foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(game.name)
                                            .font(.headline)
                                        Text(game.fileURL.pathExtension.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                Button {
                                    inspectGame(game)
                                } label: {
                                    Label("Inspect Game File", systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                                if let result = inspectionResults[game.id] {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(
                                            result.isRecognized ? "Header Recognized" : "Inspection Result",
                                            systemImage: result.isRecognized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                                        )
                                        .foregroundStyle(result.isRecognized ? .green : .orange)
                                        Text("Format: \(result.format)")
                                            .font(.caption)
                                        Text(result.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                if let error = archiveErrors[game.id] {
                                    Text("Archive error: \(error)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if let entries = archiveResults[game.id] {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("NSP Archive Contents")
                                            .font(.headline)
                                        Text("\(entries.count) entries found")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(entries) { entry in
                                            let extractionID = "\(game.id.uuidString)-\(entry.id)"
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(entry.name)
                                                    .font(.subheadline)
                                                    .lineLimit(2)
                                                Text(
                                                    ByteCountFormatter.string(
                                                        fromByteCount: Int64(clamping: entry.size),
                                                        countStyle: .file
                                                    )
                                                )
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                Button {
                                                    extractEntry(entry, from: game)
                                                } label: {
                                                    if extractingEntries.contains(extractionID) {
                                                        Label("Extracting...", systemImage: "arrow.down.doc")
                                                    } else {
                                                        Label("Extract File", systemImage: "arrow.down.doc")
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(extractingEntries.contains(extractionID))
                                                if extractingEntries.contains(extractionID) {
                                                    ProgressView(
                                                        value: extractionProgress[extractionID] ?? 0
                                                    )
                                                    .tint(.cyan)
                                                    Text(
                                                        "\(Int((extractionProgress[extractionID] ?? 0) * 100))% — " +
                                                        ByteCountFormatter.string(
                                                            fromByteCount: Int64(clamping: extractionBytes[extractionID] ?? 0),
                                                            countStyle: .file
                                                        ) +
                                                        " copied"
                                                    )
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                }
                                                if let message = extractionMessages[extractionID] {
                                                    Text(message)
                                                        .font(.caption)
                                                        .foregroundStyle(
                                                            message.hasPrefix("Saved") ? .green : .orange
                                                        )
                                                }
                                                if let result = ncaResults[extractionID] {
                                                    ncaInspectionCard(result)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.vertical, 6)
                            .swipeActions {
                                Button(role: .destructive) {
                                    deleteGame(game)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: importAction) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import games")
                }
            }
        }
    }
    private func ncaInspectionCard(_ result: NCAInspection) -> some View {
        let formattedFileSize = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: result.fileSize),
            countStyle: .file
        )
        return VStack(alignment: .leading, spacing: 8) {
            Label(
                result.isRecognized ? "NCA Signature Recognized" : "NCA Not Recognized",
                systemImage: result.isRecognized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(result.isRecognized ? .green : .orange)
            Text("Signature: \(result.magic)")
                .font(.caption)
            Text("Distribution type: \(byteDescription(result.distributionType))")
                .font(.caption)
            Text("Content type: \(byteDescription(result.contentType))")
                .font(.caption)
            Text("Key generation (old): \(byteDescription(result.keyGenerationOld))")
                .font(.caption)
            Text("Key-area encryption-key index: \(byteDescription(result.keyAreaEncryptionKeyIndex))")
                .font(.caption)
            Text("Key generation: \(byteDescription(result.keyGeneration))")
                .font(.caption)
            HStack(spacing: 6) {
                Text("Rights ID:")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(rightsIDDescription(result.rightsIDPresent))
                    .font(.caption)
                    .foregroundStyle(rightsIDColor(result.rightsIDPresent))
            }
            HStack(spacing: 6) {
                Text("Title Key Status:")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(result.titleKeyStatus ?? "Unavailable")
                    .font(.caption)
                    .foregroundStyle(titleKeyColor(result.titleKeyStatus))
            }
            Text("File size: \(formattedFileSize)")
                .font(.caption)
            Text(result.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("NCA Section Table & Filesystem Headers")
                .font(.headline)
            if result.sections.isEmpty {
                Text("No section entries were returned.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                ForEach(result.sections, id: \.index) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Section \(section.index + 1)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(section.isValid ? "Valid range" : "Empty / Check range")
                                .font(.caption)
                                .foregroundStyle(section.isValid ? .green : .orange)
                        }
                        Text("Start media unit: \(section.startMediaUnit)")
                            .font(.caption)
                        Text("End media unit: \(section.endMediaUnit)")
                            .font(.caption)
                        Text("Offset: \(section.offsetBytes) bytes")
                            .font(.caption)
                        let sectionSize = ByteCountFormatter.string(
                            fromByteCount: Int64(clamping: section.sizeBytes),
                            countStyle: .file
                        )
                        Text("Size: \(sectionSize)")
                            .font(.caption)
                        Divider()
                        Text("Filesystem type: \(hex(section.fsType)) — \(filesystemName(section.fsType))")
                            .font(.caption)
                        Text("Hash type: \(hex(section.hashType)) — \(hashName(section.hashType))")
                            .font(.caption)
                        Text("Encryption type: \(hex(section.encryptionType)) — \(encryptionName(section.encryptionType))")
                            .font(.caption)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func titleKeyColor(_ value: String?) -> Color {
        guard let value else {
            return .secondary
        }
        if value == "Matching title-key entry found" {
            return .green
        }
        if value == "Not required: no Rights ID" {
            return .green
        }
        return .orange
    }
    private func rightsIDDescription(_ value: Bool?) -> String {
        guard let value else {
            return "Unavailable"
        }
        return value ? "Present" : "Not present"
    }
    private func rightsIDColor(_ value: Bool?) -> Color {
        guard let value else {
            return .secondary
        }
        return value ? .orange : .green
    }
    private func byteDescription(_ value: UInt8?) -> String {
        guard let value else {
            return "Unavailable"
        }
        return hex(value)
    }
    private func hex(_ value: UInt8) -> String {
        String(format: "0x%02X", value)
    }
    private func filesystemName(_ value: UInt8) -> String {
        switch value {
        case 0:
            return "RomFS"
        case 1:
            return "PartitionFS"
        default:
            return "Unknown"
        }
    }
    private func hashName(_ value: UInt8) -> String {
        switch value {
        case 0:
            return "Auto"
        case 2:
            return "Hierarchical SHA-256"
        case 3:
            return "Hierarchical Integrity"
        default:
            return "Unknown"
        }
    }
    private func encryptionName(_ value: UInt8) -> String {
        switch value {
        case 0:
            return "Auto"
        case 1:
            return "None"
        case 2:
            return "AES-XTS"
        case 3:
            return "AES-CTR"
        case 4:
            return "BKTR"
        default:
            return "Unknown"
        }
    }
    private func inspectGame(_ game: ImportedGame) {
        archiveResults.removeValue(forKey: game.id)
        archiveErrors.removeValue(forKey: game.id)
        let result = GameFileInspector.inspect(game.fileURL)
        inspectionResults[game.id] = result
        guard result.format == "NSP / PFS0" else {
            return
        }
        do {
            let archive = try PFS0Archive.open(game.fileURL)
            archiveResults[game.id] = archive.entries
        } catch {
            archiveErrors[game.id] = error.localizedDescription
        }
    }
    private func extractEntry(_ entry: PFS0Entry, from game: ImportedGame) {
        let extractionID = "\(game.id.uuidString)-\(entry.id)"
        guard !extractingEntries.contains(extractionID) else {
            return
        }
        extractingEntries.insert(extractionID)
        extractionProgress[extractionID] = 0
        extractionBytes[extractionID] = 0
        extractionMessages.removeValue(forKey: extractionID)
        ncaResults.removeValue(forKey: extractionID)
        DispatchQueue.global(qos: .utility).async {
            do {
                let archive = try PFS0Archive.open(game.fileURL)
                let documents = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0]
                let outputFolder = documents
                    .appendingPathComponent("NxNativeExtracted", isDirectory: true)
                    .appendingPathComponent(game.id.uuidString, isDirectory: true)
                let savedURL = try archive.extract(
                    entry,
                    to: outputFolder
                ) { copied, total in
                    DispatchQueue.main.async {
                        extractionBytes[extractionID] = copied
                        extractionProgress[extractionID] =
                            total > 0 ? Double(copied) / Double(total) : 0
                    }
                }
                let ncaResult: NCAInspection? =
                    savedURL.pathExtension.lowercased() == "nca"
                    ? NCAInspector.inspect(savedURL)
                    : nil
                DispatchQueue.main.async {
                    extractionMessages[extractionID] = "Saved: \(savedURL.lastPathComponent)"
                    if let ncaResult {
                        ncaResults[extractionID] = ncaResult
                    }
                    extractionProgress[extractionID] = 1
                    extractingEntries.remove(extractionID)
                }
            } catch {
                DispatchQueue.main.async {
                    extractionMessages[extractionID] =
                        "Extraction failed: \(error.localizedDescription)"
                    extractingEntries.remove(extractionID)
                }
            }
        }
    }
    private func deleteGame(_ game: ImportedGame) {
        deleteAction(game)
        inspectionResults.removeValue(forKey: game.id)
        archiveResults.removeValue(forKey: game.id)
        archiveErrors.removeValue(forKey: game.id)
        let prefix = "\(game.id.uuidString)-"
        extractionMessages = extractionMessages.filter {
            !$0.key.hasPrefix(prefix)
        }
        ncaResults = ncaResults.filter {
            !$0.key.hasPrefix(prefix)
        }
        extractionProgress = extractionProgress.filter {
            !$0.key.hasPrefix(prefix)
        }
        extractionBytes = extractionBytes.filter {
            !$0.key.hasPrefix(prefix)
        }
    }
}
