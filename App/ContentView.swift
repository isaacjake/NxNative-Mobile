
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var importedGames: [ImportedGame] = []
    @State private var showingImporter = false

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
            guard case .success(let urls) = result else {
                return
            }

            for url in urls {
                let game = ImportedGame(
                    name: url.deletingPathExtension().lastPathComponent,
                    fileURL: url
                )

                if !importedGames.contains(where: {
                    $0.fileURL == url
                }) {
                    importedGames.append(game)
                }
            }
        }
    }
}

extension UTType {
    static let nspGame =
        UTType(filenameExtension: "nsp") ?? .data

    static let xciGame =
        UTType(filenameExtension: "xci") ?? .data
}

struct ImportedGame: Identifiable {
    let id = UUID()
    let name: String
    let fileURL: URL
}
