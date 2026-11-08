
import SwiftUI
import QuickLook

struct SavedSectionFilesView: View {
    @State private var files: [URL] = []
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView(
                        "No Saved Section Files",
                        systemImage: "doc",
                        description: Text(
                            "Files saved from unencrypted NCA sections will appear here."
                        )
                    )
                } else {
                    List {
                        ForEach(files, id: \.path) { file in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    file.lastPathComponent,
                                    systemImage: file.pathExtension.lowercased() == "png"
                                        ? "photo"
                                        : "film"
                                )
                                .font(.headline)
                                .lineLimit(2)

                                Text(fileSize(file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Button {
                                        previewURL = file
                                    } label: {
                                        Label(
                                            "Preview",
                                            systemImage: "eye"
                                        )
                                    }
                                    .buttonStyle(.bordered)

                                    ShareLink(item: file) {
                                        Label(
                                            "Share",
                                            systemImage: "square.and.arrow.up"
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
            .navigationTitle("Saved Section Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh saved files")
                }
            }
            .onAppear {
                loadFiles()
            }
            .sheet(item: Binding(
                get: {
                    previewURL.map { PreviewItem(url: $0) }
                },
                set: {
                    previewURL = $0?.url
                }
            )) { item in
                NavigationStack {
                    QuickLookPreviewController(url: item.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(item.url.lastPathComponent)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    previewURL = nil
                                }
                            }
                        }
                }
            }
            .alert(
                "File Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func loadFiles() {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let folder = documents.appendingPathComponent(
            "NxNativeSectionFiles",
            isDirectory: true
        )

        do {
            guard FileManager.default.fileExists(
                atPath: folder.path
            ) else {
                files = []
                return
            }

            let folders = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var found: [URL] = []

            for gameFolder in folders {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: gameFolder,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                found.append(contentsOf: contents.filter {
                    ["png", "gif"].contains(
                        $0.pathExtension.lowercased()
                    )
                })
            }

            files = found.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare(
                    $1.lastPathComponent
                ) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fileSize(_ url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )

        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        return ByteCountFormatter.string(
            fromByteCount: size,
            countStyle: .file
        )
    }
}

private struct PreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct QuickLookPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
