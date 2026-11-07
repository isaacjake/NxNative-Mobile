import SwiftUI

struct BuildView: View {
    @State private var selectedDevice = "Standard"
    @State private var buildStatus = "Not started"

    private let devices = [
        "Standard",
        "iPhone 15 or older",
        "iPhone 15 Pro or newer"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Build Configuration") {
                    Picker("Device Compatibility", selection: $selectedDevice) {
                        ForEach(devices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                }

                Section("Compilation") {
                    Label("NxNative Engine", systemImage: "cpu")
                    Text("Not connected yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("iOS Native Compiler", systemImage: "hammer")
                    Text("Not implemented yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Build Status") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(buildStatus)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        buildStatus = "Engine not configured"
                    } label: {
                        Label("Start Build", systemImage: "play.fill")
                    }
                }

                Section {
                    Text("This screen is currently a prototype. It does not compile games yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build")
        }
    }
}
