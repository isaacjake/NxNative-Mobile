import SwiftUI

private struct LibraryMetadata {
    var programID: String?
    var titleID: String?
    var applicationVersion: UInt32?
    var contentType: UInt8?
    var contentCount: Int?
    var ncaCount: Int
    var plaintextCNMTCount: Int
    var encryptedCNMTCount: Int
    var status: String
}

struct GameLibraryView: View {
    @Binding var games: [ImportedGame]

    @State private var metadata: [UUID: LibraryMetadata] = [:]
    @State private var scanning: Set<UUID> = []

    private let sections: [(kind: GameContentKind, title: String)] = [
        (.baseGame, "Base Games"),
        (.update, "Updates"),
        (.downloadableContent, "DLC"),
        (.unknown, "Unclassified Files")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.kind) { section in
                    Section(section.title) {
                        let indices = games.indices.filter {
                            games[$0].effectiveContentKind == section.kind
                        }

                        if indices.isEmpty {
                            Text("No items")
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
        }
    }

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
                    result.contentType.map { String($0) }
                )

                metadataLine(
                    "CNMT content entries",
                    result.contentCount.map(String.init)
                )

                metadataLine("NCA files found", String(result.ncaCount))
                metadataLine(
                    "Plaintext CNMT files",
                    String(result.plaintextCNMTCount)
                )
                metadataLine(
                    "Encrypted CNMT containers",
                    String(result.encryptedCNMTCount)
                )

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
            get: { games[index].effectiveContentKind },
            set: { newKind in
                games[index].contentKind =
                    newKind == .unknown ? nil : newKind
                ImportedGame.save(games)
            }
        )
    }

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
            var foundContentCount: Int?

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
                        foundContentCount = inspection.contentCount
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
                scanning.remove(game.id)
            }
        }
    }
}
