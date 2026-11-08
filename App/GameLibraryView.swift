
import SwiftUI

private struct LibraryMetadata: Codable {
    var programID: String?
    var titleID: String?
    var applicationVersion: UInt32?
    var contentType: UInt8?
    var contentCount: Int
    var ncaCount: Int
    var plaintextCNMTCount: Int
    var encryptedCNMTCount: Int
    var status: String

    var suggestedKind: GameContentKind? {
        guard let contentType else { return nil }

        switch contentType {
        case 0x80: return .baseGame
        case 0x81: return .update
        case 0x82: return .downloadableContent
        default: return nil
        }
    }

    var suggestionExplanation: String {
        guard let contentType else {
            return "No readable CNMT content type was found. Encrypted CNMT metadata is not interpreted."
        }

        switch contentType {
        case 0x80:
            return "CNMT type 0x80 identifies an Application. Suggestion only."
        case 0x81:
            return "CNMT type 0x81 identifies a Patch. Suggestion only."
        case 0x82:
            return "CNMT type 0x82 identifies Add-on Content. Suggestion only."
        default:
            return String(
                format: "CNMT type 0x%02X is not mapped.",
                contentType
            )
        }
    }
}

struct GameLibraryView: View {
    @Binding var games: [ImportedGame]

    @State private var metadata: [UUID: LibraryMetadata] =
        Self.loadMetadata()

    @State private var scanning: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedFilter = "All"

    private static let metadataStorageKey =
        "Xerenge.LibraryMetadata.v1"

    private let filters = [
        "All",
        "Base Games",
        "Updates",
        "DLC",
        "Unclassified"
    ]

    private let sections: [(kind: GameContentKind, title: String)] = [
        (.baseGame, "Base Games"),
        (.update, "Updates"),
        (.downloadableContent, "DLC"),
        (.unknown, "Unclassified Files")
    ]

    private static func loadMetadata() -> [UUID: LibraryMetadata] {
        guard let data = UserDefaults.standard.data(
            forKey: metadataStorageKey
        ),
        let saved = try? JSONDecoder().decode(
            [UUID: LibraryMetadata].self,
            from: data
        ) else {
            return [:]
        }

        return saved
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.metadataStorageKey
        )
    }

    var body: some View {
        NavigationStack {
            List {
                relationshipSummarySection

                searchFilterSection

                relationshipsSection

                ForEach(sections, id: \.kind) { section in
                    let indices = filteredIndices(for: section.kind)

                    Section(section.title) {
                        if indices.isEmpty {
                            Text("No matching items")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(indices, id: \.self) { index in
                                gameRow(at: index)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(
                text: $searchText,
                prompt: "Search games, files, or types"
            )
        }
    }

    // MARK: - Search and Filters

    private var searchFilterSection: some View {
        Section("Library Filters") {
            Picker("Show", selection: $selectedFilter) {
                ForEach(filters, id: \.self) { filter in
                    Text(filter).tag(filter)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Showing")
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(filteredGameCount) of \(games.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !searchText.isEmpty || selectedFilter != "All" {
                Button {
                    searchText = ""
                    selectedFilter = "All"
                } label: {
                    Label(
                        "Clear Search and Filters",
                        systemImage: "xmark.circle"
                    )
                }
            }
        }
    }

    private var filteredGameCount: Int {
        games.filter { game in
            matchesFilter(game) && matchesSearch(game)
        }.count
    }

    private func filteredIndices(
        for kind: GameContentKind
    ) -> [Int] {
        games.indices.filter { index in
            let game = games[index]

            return game.effectiveContentKind == kind &&
                matchesFilter(game) &&
                matchesSearch(game)
        }
    }

    private func matchesFilter(_ game: ImportedGame) -> Bool {
        switch selectedFilter {
        case "Base Games":
            return game.effectiveContentKind == .baseGame
        case "Updates":
            return game.effectiveContentKind == .update
        case "DLC":
            return game.effectiveContentKind == .downloadableContent
        case "Unclassified":
            return game.effectiveContentKind == .unknown
        default:
            return true
        }
    }

    private func matchesSearch(_ game: ImportedGame) -> Bool {
        guard !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return true
        }

        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return game.name.localizedCaseInsensitiveContains(query) ||
            game.fileName.localizedCaseInsensitiveContains(query) ||
            game.effectiveContentKind.displayName
                .localizedCaseInsensitiveContains(query)
    }

    // MARK: - Library Summary

    private var relationshipSummarySection: some View {
        let baseCount = games.filter {
            $0.effectiveContentKind == .baseGame
        }.count

        let linkedUpdates = games.filter {
            $0.effectiveContentKind == .update &&
            $0.baseGameID != nil
        }.count

        let linkedDLC = games.filter {
            $0.effectiveContentKind == .downloadableContent &&
            $0.baseGameID != nil
        }.count

        let unlinkedUpdates = games.filter {
            $0.effectiveContentKind == .update &&
            $0.baseGameID == nil
        }.count

        let unlinkedDLC = games.filter {
            $0.effectiveContentKind == .downloadableContent &&
            $0.baseGameID == nil
        }.count

        return Section("Library Summary") {
            summaryRow(
                "Base Games",
                count: baseCount,
                icon: "gamecontroller.fill"
            )

            summaryRow(
                "Linked Updates",
                count: linkedUpdates,
                icon: "arrow.up.circle"
            )

            summaryRow(
                "Linked DLC",
                count: linkedDLC,
                icon: "puzzlepiece"
            )

            summaryRow(
                "Unlinked Updates",
                count: unlinkedUpdates,
                icon: "link"
            )

            summaryRow(
                "Unlinked DLC",
                count: unlinkedDLC,
                icon: "link"
            )
        }
    }

    private func summaryRow(
        _ title: String,
        count: Int,
        icon: String
    ) -> some View {
        HStack {
            Label(title, systemImage: icon)

            Spacer()

            Text("\(count)")
                .font(.headline.monospacedDigit())
        }
    }

    // MARK: - Game Relationships

    private var relationshipsSection: some View {
        Section("Game Relationships") {
            let baseGames = games.filter {
                $0.effectiveContentKind == .baseGame
            }

            if baseGames.isEmpty {
                Text("Classify a game as Base Game to begin linking related files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(baseGames) { baseGame in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            baseGame.name,
                            systemImage: "gamecontroller.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text(
                            "Base Game Title ID: \(metadata[baseGame.id]?.titleID ?? "Not available")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                        let relatedGames = games.filter {
                            $0.baseGameID == baseGame.id
                        }

                        if relatedGames.isEmpty {
                            Text("No linked updates or DLC.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(relatedGames) { related in
                                relationshipDetails(
                                    for: related,
                                    baseGame: baseGame
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            let unlinked = games.filter {
                ($0.effectiveContentKind == .update ||
                 $0.effectiveContentKind == .downloadableContent) &&
                $0.baseGameID == nil
            }

            if !unlinked.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not linked to a base game")
                        .font(.subheadline.weight(.semibold))

                    ForEach(unlinked) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name)
                                .font(.caption.weight(.medium))

                            Text(
                                "Relationship type: \(game.effectiveContentKind.displayName)"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            Text(
                                "CNMT Title ID: \(metadata[game.id]?.titleID ?? "Not available")"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                            Text("Base Game: Not linked")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func relationshipDetails(
        for related: ImportedGame,
        baseGame: ImportedGame
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(
                    systemName:
                        related.effectiveContentKind == .update
                        ? "arrow.up.circle"
                        : "puzzlepiece"
                )

                Text(related.name)
                    .font(.caption.weight(.medium))

                Spacer()

                Text(related.effectiveContentKind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Linked Base Game: \(baseGame.name)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(
                "CNMT Title ID: \(metadata[related.id]?.titleID ?? "Not available")"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            Text(
                "Relationship type: \(related.effectiveContentKind.displayName)"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Game Rows

    private func gameRow(at index: Int) -> some View {
        let game = games[index]

        return VStack(alignment: .leading, spacing: 8) {
            Text(game.name)
                .font(.headline)

            Text(game.fileURL.pathExtension.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Classification: \(game.effectiveContentKind.displayName)")
                .font(.caption)

            if game.effectiveContentKind == .update ||
               game.effectiveContentKind == .downloadableContent {
                let baseGames = games.filter {
                    $0.effectiveContentKind == .baseGame &&
                    $0.id != game.id
                }

                Picker(
                    "Linked Base Game",
                    selection: relationshipBinding(at: index)
                ) {
                    Text("Not linked")
                        .tag(Optional<UUID>.none)

                    ForEach(baseGames) { baseGame in
                        Text(baseGame.name)
                            .tag(Optional(baseGame.id))
                    }
                }
                .pickerStyle(.menu)
            }

            if let result = metadata[game.id] {
                Divider()

                Text("Game Metadata")
                    .font(.subheadline.weight(.semibold))

                metadataLine("NCA Program ID", result.programID)
                metadataLine("CNMT Title ID", result.titleID)

                metadataLine(
                    "CNMT application version (raw)",
                    result.applicationVersion.map(String.init)
                )

                metadataLine(
                    "CNMT content type",
                    result.contentType.map {
                        String(format: "0x%02X", $0)
                    }
                )

                metadataLine(
                    "CNMT content entries",
                    String(result.contentCount)
                )

                metadataLine(
                    "NCA files found",
                    String(result.ncaCount)
                )

                metadataLine(
                    "Plaintext CNMT files",
                    String(result.plaintextCNMTCount)
                )

                metadataLine(
                    "Encrypted CNMT containers",
                    String(result.encryptedCNMTCount)
                )

                Divider()

                if let suggestion = result.suggestedKind {
                    Text("Suggested classification: \(suggestion.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)

                    Text(result.suggestionExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if game.effectiveContentKind != suggestion {
                        Button {
                            games[index].contentKind = suggestion
                            ImportedGame.save(games)
                        } label: {
                            Label(
                                "Apply \(suggestion.displayName) Suggestion",
                                systemImage: "checkmark.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("No classification suggestion")
                        .font(.subheadline.weight(.semibold))

                    Text(result.suggestionExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(result.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                scanMetadata(for: game)
            } label: {
                if scanning.contains(game.id) {
                    Label("Scanning Metadata...", systemImage: "hourglass")
                } else {
                    Label(
                        "Scan Game Metadata",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(scanning.contains(game.id))

            Picker(
                "Classification",
                selection: classificationBinding(at: index)
            ) {
                Text("Unclassified").tag(GameContentKind.unknown)
                Text("Base Game").tag(GameContentKind.baseGame)
                Text("Update").tag(GameContentKind.update)
                Text("DLC").tag(GameContentKind.downloadableContent)
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings

    private func relationshipBinding(
        at index: Int
    ) -> Binding<UUID?> {
        Binding(
            get: {
                games[index].baseGameID
            },
            set: { newID in
                games[index].baseGameID = newID
                ImportedGame.save(games)
            }
        )
    }

    private func metadataLine(
        _ label: String,
        _ value: String?
    ) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundStyle(.secondary)

            Spacer()

            Text(value ?? "Not detected")
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func classificationBinding(
        at index: Int
    ) -> Binding<GameContentKind> {
        Binding(
            get: {
                games[index].effectiveContentKind
            },
            set: { newKind in
                games[index].contentKind =
                    newKind == .unknown ? nil : newKind

                ImportedGame.save(games)
            }
        )
    }

    // MARK: - Metadata Scanner

    private func scanMetadata(for game: ImportedGame) {
        guard !scanning.contains(game.id) else { return }

        scanning.insert(game.id)

        DispatchQueue.global(qos: .utility).async {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

            let folder = documents
                .appendingPathComponent(
                    "NxNativeExtracted",
                    isDirectory: true
                )
                .appendingPathComponent(
                    game.id.uuidString,
                    isDirectory: true
                )

            var foundProgramID: String?
            var foundTitleID: String?
            var foundVersion: UInt32?
            var foundContentType: UInt8?
            var foundContentCount = 0

            var ncaCount = 0
            var plaintextCNMTCount = 0
            var encryptedCNMTCount = 0

            var status = "Metadata scan finished."

            do {
                guard FileManager.default.fileExists(
                    atPath: folder.path
                ) else {
                    throw CocoaError(.fileNoSuchFile)
                }

                guard let enumerator = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    throw CocoaError(.fileReadUnknown)
                }

                var ncaFiles: [URL] = []
                var cnmtFiles: [URL] = []

                for case let file as URL in enumerator {
                    let values = try? file.resourceValues(
                        forKeys: [.isRegularFileKey]
                    )

                    guard values?.isRegularFile == true else {
                        continue
                    }

                    let fileName = file.lastPathComponent.lowercased()
                    let extensionName = file.pathExtension.lowercased()

                    if extensionName == "nca" {
                        ncaFiles.append(file)

                        if fileName.hasSuffix(".cnmt.nca") {
                            encryptedCNMTCount += 1
                        }
                    }

                    if extensionName == "cnmt" {
                        cnmtFiles.append(file)
                    }
                }

                ncaCount = ncaFiles.count
                plaintextCNMTCount = cnmtFiles.count

                for file in ncaFiles {
                    let inspection = NCAInspector.inspect(file)

                    if inspection.isRecognized,
                       let programID = inspection.programID {
                        foundProgramID = programID
                        break
                    }
                }

                for file in cnmtFiles {
                    let inspection = CNMTInspector.inspect(file)

                    if inspection.isRecognized {
                        foundTitleID = inspection.titleID
                        foundVersion = inspection.version
                        foundContentType = inspection.contentType
                        foundContentCount = inspection.contentCount ?? 0
                        break
                    }
                }

                if ncaFiles.isEmpty && cnmtFiles.isEmpty {
                    status = "No extracted NCA or plaintext CNMT files found."
                } else if foundProgramID == nil && foundTitleID == nil {
                    if encryptedCNMTCount > 0 {
                        status = "Encrypted CNMT containers found. Their metadata is not decrypted or parsed."
                    } else {
                        status = "Files found, but readable metadata was not recognized."
                    }
                } else if encryptedCNMTCount > 0 {
                    status = "Readable metadata found. Encrypted CNMT containers were detected but not parsed."
                } else {
                    status = "Readable metadata found in extracted files."
                }

            } catch {
                status = "No extracted metadata folder found. Inspect and extract game files first."
            }

            let result = LibraryMetadata(
                programID: foundProgramID,
                titleID: foundTitleID,
                applicationVersion: foundVersion,
                contentType: foundContentType,
                contentCount: foundContentCount,
                ncaCount: ncaCount,
                plaintextCNMTCount: plaintextCNMTCount,
                encryptedCNMTCount: encryptedCNMTCount,
                status: status
            )

            DispatchQueue.main.async {
                metadata[game.id] = result
                saveMetadata()
                scanning.remove(game.id)
            }
        }
    }
}
