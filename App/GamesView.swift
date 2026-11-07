
import SwiftUI

struct GamesView: View {
    let games: [ImportedGame]
    let importAction: () -> Void
    let deleteAction: (ImportedGame) -> Void

    @State private var inspectionResults: [UUID: GameFileInspection] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "No Games Imported",
                            systemImage: "gamecontroller"
                        )
                    } description: {
                        Text(
                            "Import a legally obtained NSP or XCI game file to get started."
                        )
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

                                        Text(
                                            game.fileURL.pathExtension.uppercased()
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }

                                Button {
                                    inspectionResults[game.id] =
                                        GameFileInspector.inspect(game.fileURL)
                                } label: {
                                    Label(
                                        "Inspect Game File",
                                        systemImage: "doc.text.magnifyingglass"
                                    )
                                }
                                .buttonStyle(.bordered)

                                if let result = inspectionResults[game.id] {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(
                                            result.isRecognized
                                                ? "Header Recognized"
                                                : "Inspection Result",
                                            systemImage: result.isRecognized
                                                ? "checkmark.circle.fill"
                                                : "exclamationmark.triangle.fill"
                                        )
                                        .foregroundStyle(
                                            result.isRecognized ? .green : .orange
                                        )

                                        Text("Format: \(result.format)")
                                            .font(.caption)

                                        Text(result.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .background(
                                        Color.secondary.opacity(0.10)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.vertical, 6)
                            .swipeActions {
                                Button(role: .destructive) {
                                    deleteAction(game)
                                    inspectionResults.removeValue(
                                        forKey: game.id
                                    )
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
}
