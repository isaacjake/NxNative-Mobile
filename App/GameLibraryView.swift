import SwiftUI

private struct LibraryMetadata {
    var programID: String?
    var cnmtVersion: UInt32?
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

                Text("Program ID: \(result.programID ?? "Not detected")")
                    .font(.caption)

                Text(
                    result.cnmtVersion.map {
                        "CNMT version value: \($0)"
                    } ?? "CNMT version: Not detected"
                )
                .font(.caption)

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
                    Label("Scan Game Metadata", systemImage: "doc.text.magnifyingglass")
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
            var foundVersion: UInt32?
            var status = "Metadata scan finished."

            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                let ncaFiles = files.filter {
                    $0.pathExtension.lowercased() == "nca"
                }

                let cnmtFiles = files.filter {
                    $0.pathExtension.lowercased() == "cnmt"
                }

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

                    if inspection.isRecognized,
                       let version = inspection.version {
                        foundVersion = version
                        break
                    }
                }

                if ncaFiles.isEmpty && cnmtFiles.isEmpty {
                    status = "No extracted NCA or plaintext CNMT files found."
                } else if foundProgramID == nil && foundVersion == nil {
                    status = "Files found, but metadata was not recognized."
                } else {
                    status = "Metadata read from available extracted files."
                }

            } catch {
                status = "No extracted metadata folder found. Inspect and extract game files first."
            }

            let result = LibraryMetadata(
                programID: foundProgramID,
                cnmtVersion: foundVersion,
                status: status
            )

            DispatchQueue.main.async {
                metadata[game.id] = result
                scanning.remove(game.id)
            }
        }
    }
}
