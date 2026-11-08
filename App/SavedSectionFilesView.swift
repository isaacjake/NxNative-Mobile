
import SwiftUI
import QuickLook
import UIKit

struct SavedSectionFilesView: View {
    @State private var groups: [SavedFileGroup] = []
    @State private var previewItem: PreviewItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Saved Section Files",
                        systemImage: "folder",
                        description: Text(
                            "Files saved from unencrypted NCA sections will appear here."
                        )
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            Section(group.gameName) {
                                ForEach(group.files) { file in
                                    VStack(alignment: .leading, spacing: 9) {
                                        Label {
                                            Text(file.url.lastPathComponent)
                                                .font(.headline)
                                                .lineLimit(2)
                                        } icon: {
                                            Image(systemName: file.icon)
                                                .foregroundStyle(.cyan)
                                        }

                                        HStack(spacing: 12) {
                                            Text(file.format)
                                            Text(file.size)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        HStack {
                                            Button {
                                                previewItem = PreviewItem(url: file.url)
                                            } label: {
                                                Label("Preview", systemImage: "eye")
                                            }
                                            .buttonStyle(.bordered)

                                            ShareLink(item: file.url) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Files")
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
            .sheet(item: $previewItem) { item in
                NavigationStack {
                    QuickLookPreviewController(url: item.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(item.url.lastPathComponent)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    previewItem = nil
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

        let root = documents.appendingPathComponent(
            "NxNativeSectionFiles",
            isDirectory: true
        )

        do {
            guard FileManager.default.fileExists(atPath: root.path) else {
                groups = []
                return
            }

            let savedGames = ImportedGame.loadSaved()
            let gameNames = Dictionary(
                uniqueKeysWithValues: savedGames.map {
                    ($0.id.uuidString.lowercased(), $0.name)
                }
            )

            let folders = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var loadedGroups: [SavedFileGroup] = []

            for folder in folders {
                let values = try folder.resourceValues(
                    forKeys: [.isDirectoryKey]
                )

                guard values.isDirectory == true else {
                    continue
                }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                let savedFiles = contents.compactMap { url -> SavedSectionFile? in
                    let ext = url.pathExtension.lowercased()

                    guard ext == "png" || ext == "gif" else {
                        return nil
                    }

                    let attributes = try? FileManager.default.attributesOfItem(
                        atPath: url.path
                    )

                    let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

                    return SavedSectionFile(
                        url: url,
                        size: ByteCountFormatter.string(
                            fromByteCount: bytes,
                            countStyle: .file
                        )
                    )
                }
                .sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                        $1.url.lastPathComponent
                    ) == .orderedAscending
                }

                if !savedFiles.isEmpty {
                    let folderID = folder.lastPathComponent.lowercased()

                    loadedGroups.append(
                        SavedFileGroup(
                            id: folderID,
                            gameName: gameNames[folderID] ?? "Unknown Game",
                            files: savedFiles
                        )
                    )
                }
            }

            groups = loadedGroups.sorted {
                $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SavedFileGroup: Identifiable {
    let id: String
    let gameName: String
    let files: [SavedSectionFile]
}

private struct SavedSectionFile: Identifiable {
    let url: URL
    let size: String

    var id: String { url.path }

    var format: String {
        switch url.pathExtension.lowercased() {
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        default: return "File"
        }
    }

    var icon: String {
        url.pathExtension.lowercased() == "png" ? "photo" : "film"
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
