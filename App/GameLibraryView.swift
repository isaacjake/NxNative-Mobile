import SwiftUI

struct GameLibraryView: View {
    @Binding var games: [ImportedGame]

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
        VStack(alignment: .leading, spacing: 8) {
            Text(games[index].name)
                .font(.headline)

            Text(games[index].fileURL.pathExtension.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Classification", selection: classificationBinding(at: index)) {
                Text("Unclassified").tag(GameContentKind.unknown)
                Text("Base Game").tag(GameContentKind.baseGame)
                Text("Update").tag(GameContentKind.update)
                Text("DLC").tag(GameContentKind.downloadableContent)
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }

    private func classificationBinding(at index: Int) -> Binding<GameContentKind> {
        Binding(
            get: { games[index].effectiveContentKind },
            set: { newKind in
                games[index].contentKind =
                    newKind == .unknown ? nil : newKind
                ImportedGame.save(games)
            }
        )
    }
}
