
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
                                            systemImage: result.isRecognized
                                                ? "checkmark.circle.fill"
                                                : "exclamationmark.triangle.fill"
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
                                                        ProgressView()
                                                    } else {
                                                        Label("Extract File", systemImage: "arrow.down.doc")
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(extractingEntries.contains(extractionID))

                                                if let message = extractionMessages[extractionID] {
                                                    Text(message)
                                                        .font(.caption)
                                                        .foregroundStyle(message.hasPrefix("Saved") ? .green : .orange)
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
        extractionMessages.removeValue(forKey: extractionID)

        DispatchQueue.global(qos: .userInitiated).async {
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
                )

                DispatchQueue.main.async {
                    extractionMessages[extractionID] =
                        "Saved: \(savedURL.lastPathComponent)"
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
    }
}
