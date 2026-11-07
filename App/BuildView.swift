import SwiftUI
import UniformTypeIdentifiers

struct BuildView: View {
    @State private var showingKeysPicker = false
    @State private var showingTitleKeysPicker = false

    @State private var hasKeys = KeyManager.hasKeys
    @State private var hasTitleKeys = KeyManager.hasTitleKeys

    @State private var statusMessage = ""
    @State private var showingStatus = false

    var body: some View {
        NavigationStack {
            List {
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

                    Text("Key verification does not yet decrypt or compile games.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build")
            .onAppear {
                hasKeys = KeyManager.hasKeys
                hasTitleKeys = KeyManager.hasTitleKeys
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
