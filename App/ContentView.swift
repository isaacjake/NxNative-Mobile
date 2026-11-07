
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var importedGames = ImportedGame.loadSaved()
    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                gameCount: importedGames.count,
                importAction: { showingImporter = true }
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(0)

            GamesView(
                games: importedGames,
                importAction: { showingImporter = true }
            )
            .tabItem {
                Label("Games", systemImage: "gamecontroller.fill")
            }
            .tag(1)

            BuildView()
                .tabItem {
                    Label("Build", systemImage: "hammer.fill")
                }
                .tag(2)

            OutputView()
                .tabItem {
                    Label("Output", systemImage: "archivebox.fill")
                }
                .tag(3)
        }
        .tint(.cyan)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.nspGame, .xciGame],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importGames(urls)

            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            "Import Error",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                importError = nil
            }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func importGames(_ urls: [URL]) {
        let manager = FileManager.default

        let folder = manager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("NxNativeGames")

        do {
            try manager.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let fileName = UUID().uuidString + "." +
                    url.pathExtension.lowercased()

                let destination = folder.appendingPathComponent(fileName)

                try manager.copyItem(
                    at: url,
                    to: destination
                )

                let game = ImportedGame(
                    name: url.deletingPathExtension().lastPathComponent,
                    fileName: fileName
                )

                importedGames.append(game)
            }

            ImportedGame.save(importedGames)

        } catch {
            importError = error.localizedDescription
        }
    }
}

extension UTType {
    static let nspGame =
        UTType(filenameExtension: "nsp") ?? .data

    static let xciGame =
        UTType(filenameExtension: "xci") ?? .data
}

struct ImportedGame: Identifiable, Codable {
    let id: UUID
    let name: String
    let fileName: String

    init(name: String, fileName: String) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
    }

    var fileURL: URL {
        let folder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("NxNativeGames")

        return folder.appendingPathComponent(fileName)
    }

    private static var libraryURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("games-library.json")
    }

    static func loadSaved() -> [ImportedGame] {
        guard let data = try? Data(contentsOf: libraryURL),
              let games = try? JSONDecoder().decode(
                [ImportedGame].self,
                from: data
              ) else {
            return []
        }

        return games
    }

    static func save(_ games: [ImportedGame]) {
        guard let data = try? JSONEncoder().encode(games) else {
            return
        }

        try? data.write(to: libraryURL, options: .atomic)
    }
}
