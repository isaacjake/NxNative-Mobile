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
