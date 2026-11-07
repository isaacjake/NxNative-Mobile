import SwiftUI

struct OutputView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Builds Yet", systemImage: "archivebox")
            } description: {
                Text("Completed native iOS builds will appear here.")
            } actions: {
                Text("Your generated IPA files will be listed here once compilation is implemented.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("Output")
        }
    }
}
