
import SwiftUI
import UniformTypeIdentifiers

struct BuildView: View {
    @State private var showingKeysPicker = false
    @State private var showingTitleKeysPicker = false

    @State private var hasKeys = KeyManager.hasKeys
    @State private var hasTitleKeys = KeyManager.hasTitleKeys

    @State private var statusMessage = ""
    @State private var showingStatus = false

    @State private var games = ImportedGame.loadSaved()
    @State private var selectedGameID: UUID?
    @State private var preflightMessage = ""
    @State private var preflightLines: [String] = []
    @State private var isRunningPreflight = false

    private var selectedGame: ImportedGame? {
        games.first { $0.id == selectedGameID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Game Preflight") {
                    if games.isEmpty {
                        ContentUnavailableView(
                            "No Imported Games",
                            systemImage: "gamecontroller",
                            description: Text("Import a game in the Games tab first.")
                        )
                    } else {
                        Picker("Select Game", selection: $selectedGameID) {
                            Text("Choose a game")
                                .tag(UUID?.none)

                            ForEach(games) { game in
                                Text(game.name)
                                    .tag(Optional(game.id))
                            }
                        }

                        if let game = selectedGame {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(game.name)
                                    .font(.headline)

                                Text(game.fileURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                runPreflight(for: game)
                            } label: {
                                if isRunningPreflight {
                                    Label("Checking Game...", systemImage: "hourglass")
                                } else {
                                    Label("Run Game Preflight", systemImage: "checkmark.shield")
                                }
                            }
                            .disabled(isRunningPreflight)

                            if !preflightMessage.isEmpty {
                                Label(
                                    preflightMessage,
                                    systemImage: preflightMessage.hasPrefix("Preflight complete")
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.subheadline)
                                .foregroundStyle(
                                    preflightMessage.hasPrefix("Preflight complete")
                                        ? .green
                                        : .orange
                                )
                            }

                            ForEach(Array(preflightLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Game Keys") {
                    HStack {
                        Label(
                            hasKeys ? "prod.keys imported" : "No prod.keys imported",
                            systemImage: hasKeys ? "checkmark.circle.fill" : "key"
                        )
                        Spacer()
                        Text(hasKeys ? "Ready" : "Required")
                            .foregroundStyle(hasKeys ? .green : .orange)
                    }

                    Button {
                        showingKeysPicker = true
                    } label: {
                        Label("Import prod.keys", systemImage: "folder")
                    }

                    if hasKeys {
                        Button {
                            verifyHeaderKey()
                        } label: {
                            Label("Verify NCA Header Key", systemImage: "key.horizontal")
                        }

                        Button("Remove saved prod.keys", role: .destructive) {
                            do {
                                try KeyManager.deleteKeys()
                                hasKeys = false
                                statusMessage = "Saved prod.keys removed."
                                showingStatus = true
                            } catch {
                                showError(error)
                            }
                        }
                    }
                }

                Section("Title Keys") {
                    HStack {
                        Label(
                            hasTitleKeys ? "title.keys imported" : "No title.keys imported",
                            systemImage: hasTitleKeys ? "checkmark.circle.fill" : "key"
                        )
                        Spacer()
                        Text(hasTitleKeys ? "Imported" : "Not imported")
                            .foregroundStyle(hasTitleKeys ? .green : .secondary)
                    }

                    Button {
                        showingTitleKeysPicker = true
                    } label: {
                        Label("Import title.keys", systemImage: "folder")
                    }

                    if hasTitleKeys {
                        Button("Remove saved title.keys", role: .destructive) {
                            do {
                                try KeyManager.deleteTitleKeys()
                                hasTitleKeys = false
                                statusMessage = "Saved title.keys removed."
                                showingStatus = true
                            } catch {
                                showError(error)
                            }
                        }
                    }

                    Text("Title keys are stored separately from prod.keys in this iPhone's Keychain. Key values are never displayed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("NxNative Engine") {
                    Label("Engine not connected", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)

                    Text("The game compiler has not yet been integrated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("iPhone Runtime") {
                    Label("iOS 26 or later", systemImage: "checkmark.circle")
                    Label("iPhone 15 Pro or newer", systemImage: "checkmark.circle")
                }

                Section("Development Goal") {
                    Text("Develop an on-device game compilation workflow without a Mac, Xcode, or hosted runners.")
                        .font(.footnote)

                    Text("Preflight checks archive structure only. It does not decrypt or compile game content.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build")
            .onAppear {
                games = ImportedGame.loadSaved()
                hasKeys = KeyManager.hasKeys
                hasTitleKeys = KeyManager.hasTitleKeys

                if selectedGameID == nil {
                    selectedGameID = games.first?.id
                }
            }
            .onChange(of: selectedGameID) {
                preflightMessage = ""
                preflightLines = []
            }
            .fileImporter(
                isPresented: $showingKeysPicker,
                allowedContentTypes: [.data, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }

                    do {
                        try KeyManager.importKeys(from: url)
                        hasKeys = KeyManager.hasKeys
                        statusMessage = "prod.keys saved securely on this iPhone."
                        showingStatus = true
                    } catch {
                        showError(error)
                    }

                case .failure(let error):
                    showError(error)
                }
            }
            .fileImporter(
                isPresented: $showingTitleKeysPicker,
                allowedContentTypes: [.data, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }

                    do {
                        try KeyManager.importTitleKeys(from: url)
                        hasTitleKeys = KeyManager.hasTitleKeys
                        statusMessage = "title.keys saved securely on this iPhone."
                        showingStatus = true
                    } catch {
                        showError(error)
                    }

                case .failure(let error):
                    showError(error)
                }
            }
            .alert("Key Status", isPresented: $showingStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage)
            }
        }
    }

    private func runPreflight(for game: ImportedGame) {
        guard !isRunningPreflight else { return }

        isRunningPreflight = true
        preflightMessage = "Checking archive structure..."
        preflightLines = []

        DispatchQueue.global(qos: .userInitiated).async {
            var lines: [String] = []

            let inspection = GameFileInspector.inspect(game.fileURL)

            lines.append("File format: \(inspection.format)")
            lines.append("Header check: \(inspection.isRecognized ? "Recognized" : "Not recognized")")

            if !inspection.isRecognized {
                DispatchQueue.main.async {
                    preflightMessage = "Preflight could not recognize this game file."
                    preflightLines = lines + [inspection.message]
                    isRunningPreflight = false
                }
                return
            }

            if inspection.format == "XCI" {
                lines.append("XCI directory inventory: Not yet supported")
                lines.append("Next requirement: XCI partition and filesystem reader")
                lines.append("Game content: Not decrypted or compiled")

                DispatchQueue.main.async {
                    preflightMessage = "Preflight complete — additional XCI support needed."
                    preflightLines = lines
                    isRunningPreflight = false
                }
                return
            }

            do {
                let archive = try PFS0Archive.open(game.fileURL)
                let entries = archive.entries

                let ncaCount = entries.filter {
                    $0.name.lowercased().hasSuffix(".nca")
                }.count

                let ticketCount = entries.filter {
                    $0.name.lowercased().hasSuffix(".tik")
                }.count

                let certificateCount = entries.filter {
                    $0.name.lowercased().hasSuffix(".cert")
                }.count

                let cnmtCount = entries.filter {
                    $0.name.lowercased().hasSuffix(".cnmt")
                }.count

                let otherCount = entries.count
                    - ncaCount
                    - ticketCount
                    - certificateCount
                    - cnmtCount

                let totalBytes = entries.reduce(UInt64(0)) {
                    $0 &+ $1.size
                }

                let formattedSize = ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: totalBytes),
                    countStyle: .file
                )

                lines.append("PFS0 directory: Valid")
                lines.append("Archive entries: \(entries.count)")
                lines.append("NCA files: \(ncaCount)")
                lines.append("Ticket files: \(ticketCount)")
                lines.append("Certificate files: \(certificateCount)")
                lines.append("Plaintext CNMT files: \(cnmtCount)")
                lines.append("Other entries: \(otherCount)")
                lines.append("Total listed entry size: \(formattedSize)")
                lines.append("NCA content: Not decrypted")
                lines.append("Native compilation: Not yet implemented")

                DispatchQueue.main.async {
                    preflightMessage = "Preflight complete — archive metadata validated."
                    preflightLines = lines
                    isRunningPreflight = false
                }
            } catch {
                DispatchQueue.main.async {
                    preflightMessage = "Preflight failed — archive could not be read."
                    preflightLines = lines + [error.localizedDescription]
                    isRunningPreflight = false
                }
            }
        }
    }

    private func verifyHeaderKey() {
        do {
            let key = try KeyManager.loadHeaderKey()

            statusMessage = key.count == 32
                ? "NCA header key entry found. This checks its format and length, not whether it is the correct key."
                : "NCA header key has an unexpected length."

            showingStatus = true
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        statusMessage = error.localizedDescription
        showingStatus = true
    }
}
