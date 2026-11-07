
import SwiftUI

struct BuildView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("NxNative Engine") {
                    Label("Engine not connected", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)

                    Text("The NxNative compiler has not yet been integrated into this app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Official Build Requirements") {
                    requirement("macOS 26.6 or later")
                    requirement("Xcode 27.2")
                    requirement("Python 3.12 or later")
                    requirement("Your own game files and keys")
                }

                Section("iPhone Runtime Requirements") {
                    requirement("iOS 26 or later")
                    requirement("iPhone 15 Pro or newer")
                }

                Section("Our Development Goal") {
                    Text("Build a workflow that runs entirely on the iPhone, without a Mac, Xcode, or hosted build runners.")
                        .font(.footnote)

                    Text("This capability is not implemented yet. We need to develop and test an alternative to the official Mac-based build pipeline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build")
        }
    }

    private func requirement(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle")
            .font(.subheadline)
    }
}
