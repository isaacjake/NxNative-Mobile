
import SwiftUI
import UniformTypeIdentifiers

struct BuildView: View {
    @State private var showingKeysPicker = false
    @State private var hasKeys = KeyManager.hasKeys
    @State private var statusMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            List {
                Section("Game Keys") {
                    HStack {
                        Label(
                            hasKeys ? "Keys imported" : "No keys imported",
                            systemImage: hasKeys
                                ? "checkmark.circle.fill"
                                : "key"
                        )
                        Spacer()
                        Text(hasKeys ? "Ready" : "Required")
                            .foregroundStyle(
                                hasKeys ? .green : .orange
                            )
                    }

                    Button {
                        showingKeysPicker = true
                    } label: {
                        Label(
                            "Import prod.keys",
                            systemImage: "folder"
                        )
                    }

                    if hasKeys {
                        Button("Remove saved keys", role: .destructive) {
                            do {
                                try KeyManager.deleteKeys()
                                hasKeys = false
                                statusMessage = "Saved keys removed."
                            } catch {
                                statusMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }

                    Text("Your keys are stored in this app's iOS Keychain. They are not uploaded to GitHub.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("NxNative Engine") {
                    Label(
                        "Engine not connected",
                        systemImage: "exclamationmark.triangle"
                    )
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

                    Text("This capability is still under development. Importing keys does not yet decrypt or compile games.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build")
            .onAppear {
                hasKeys = KeyManager.hasKeys
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
                        statusMessage = "Keys saved securely on this iPhone."
                    } catch {
                        statusMessage = error.localizedDescription
                        showingError = true
                    }

                case .failure(let error):
                    statusMessage = error.localizedDescription
                    showingError = true
                }
            }
            .alert("Keys Import", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage)
            }
            .alert(
                "Import Status",
                isPresented: Binding(
                    get: { !statusMessage.isEmpty && !showingError },
                    set: { if !$0 { statusMessage = "" } }
                )
            ) {
                Button("OK", role: .cancel) {
                    statusMessage = ""
                }
            } message: {
                Text(statusMessage)
            }
        }
    }
}
