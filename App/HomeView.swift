import SwiftUI

struct HomeView: View {
    let gameCount: Int
    let importAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NxNative Mobile")
                            .font(.largeTitle.bold())

                        Text("Switch game compilation for iOS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: importAction) {
                        Label("Import Switch Games", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(spacing: 12) {
                        summaryCard(
                            title: "Imported Games",
                            value: "\(gameCount)",
                            symbol: "gamecontroller.fill"
                        )

                        summaryCard(
                            title: "Build Status",
                            value: "Not started",
                            symbol: "hammer.fill"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Status")
                            .font(.headline)

                        Text("The app interface is being set up. On-device game compilation is not implemented yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .navigationTitle("Home")
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
