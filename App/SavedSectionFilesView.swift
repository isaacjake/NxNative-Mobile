
import SwiftUI
import QuickLook
import UIKit

struct SavedSectionFilesView: View {
    @State private var groups: [SavedFileGroup] = []
    @State private var previewItem: PreviewItem?
    @State private var detailItem: FileDetailItem?
    @State private var pendingDelete: SavedSectionFile?
    @State private var errorMessage: String?

    private let supportedExtensions: Set<String> = [
        "png", "gif", "jpg", "jpeg", "txt", "json", "xml", "pdf"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Saved Section Files",
                        systemImage: "folder",
                        description: Text(
                            "Supported files saved from unencrypted NCA sections will appear here."
                        )
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            Section(group.gameName) {
                                ForEach(group.files) { file in
                                    HStack(alignment: .top, spacing: 12) {
                                        SavedFileThumbnail(url: file.url)

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(file.url.lastPathComponent)
                                                .font(.headline)
                                                .lineLimit(2)

                                            HStack(spacing: 10) {
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

                                                Button {
                                                    detailItem = FileDetailItem(
                                                        url: file.url,
                                                        gameName: group.gameName
                                                    )
                                                } label: {
                                                    Label("Details", systemImage: "info.circle")
                                                }
                                                .buttonStyle(.bordered)

                                                ShareLink(item: file.url) {
                                                    Image(systemName: "square.and.arrow.up")
                                                }
                                                .buttonStyle(.bordered)
                                                .accessibilityLabel("Share file")

                                                Button(role: .destructive) {
                                                    pendingDelete = file
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                                .accessibilityLabel("Delete saved file")
                                            }
                                        }
                                    }
                                    .padding(.vertical, 6)
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
            .sheet(item: $detailItem) { item in
                NavigationStack {
                    FileDetailsView(
                        url: item.url,
                        gameName: item.gameName
                    )
                }
            }
            .confirmationDialog(
                "Delete Saved File?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete File", role: .destructive) {
                    deletePendingFile()
                }

                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text(
                    "This removes the saved copy from NxNative. Your original NSP or XCI game file will not be affected."
                )
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

                    guard supportedExtensions.contains(ext) else {
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
                $0.gameName.localizedCaseInsensitiveCompare($1.gameName)
                    == .orderedAscending
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingFile() {
        guard let file = pendingDelete else {
            return
        }

        do {
            try FileManager.default.removeItem(at: file.url)
            pendingDelete = nil
            loadFiles()
        } catch {
            pendingDelete = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct FileDetailsView: View {
    let url: URL
    let gameName: String

    @Environment(\.dismiss) private var dismiss

    private var fileBytes: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )

        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private var format: String {
        SavedSectionFile.formatName(for: url)
    }

    var body: some View {
        List {
            Section("File") {
                detailRow("File name", value: url.lastPathComponent)
                detailRow("Format", value: format)

                detailRow(
                    "Size",
                    value: ByteCountFormatter.string(
                        fromByteCount: fileBytes,
                        countStyle: .file
                    )
                )

                detailRow("Exact size", value: "\(fileBytes) bytes")
            }

            Section("Game") {
                detailRow("Game name", value: gameName)
            }

            Section("Storage") {
                detailRow(
                    "Folder",
                    value: url.deletingLastPathComponent().lastPathComponent
                )

                detailRow("File location", value: url.path)
            }

            Section {
                ShareLink(item: url) {
                    Label("Share This File", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("File Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

private struct SavedFileThumbnail: View {
    let url: URL

    private var symbol: String {
        switch url.pathExtension.lowercased() {
        case "txt":
            return "text.alignleft"
        case "json":
            return "curlybraces"
        case "xml":
            return "chevron.left.forwardslash.chevron.right"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    var id: String {
        url.path
    }

    var format: String {
        Self.formatName(for: url)
    }

    static func formatName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":
            return "PNG Image"
        case "gif":
            return "GIF Image"
        case "jpg", "jpeg":
            return "JPEG Image"
        case "txt":
            return "Text File"
        case "json":
            return "JSON Data"
        case "xml":
            return "XML Document"
        case "pdf":
            return "PDF Document"
        default:
            return "File"
        }
    }
}

private struct PreviewItem: Identifiable {
    let url: URL

    var id: String {
        url.path
    }
}

private struct FileDetailItem: Identifiable {
    let url: URL
    let gameName: String

    var id: String {
        url.path
    }
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
