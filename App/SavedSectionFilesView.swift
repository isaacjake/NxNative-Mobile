
import SwiftUI
import QuickLook
import UIKit

private enum SavedFileFilter: String, CaseIterable, Identifiable {
    case all, images, videos, documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .images: return "Images"
        case .videos: return "Videos"
        case .documents: return "Documents"
        }
    }

    func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()

        switch self {
        case .all:
            return true
        case .images:
            return ["png", "gif", "jpg", "jpeg", "heic"].contains(ext)
        case .videos:
            return ["mp4", "mov", "m4v"].contains(ext)
        case .documents:
            return ["pdf", "txt", "json", "xml"].contains(ext)
        }
    }
}

private enum SavedFileSort: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case newest
    case largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending: return "Name (A–Z)"
        case .nameDescending: return "Name (Z–A)"
        case .newest: return "Newest First"
        case .largest: return "Largest First"
        }
    }
}

struct SavedSectionFilesView: View {
    @State private var groups: [SavedFileGroup] = []
    @State private var selectedFilter: SavedFileFilter = .all
    @State private var selectedSort: SavedFileSort = .nameAscending
    @State private var searchText = ""
    @State private var previewItem: PreviewItem?
    @State private var detailItem: FileDetailItem?
    @State private var pendingDelete: SavedSectionFile?
    @State private var errorMessage: String?

    private let supportedExtensions: Set<String> = [
        "png", "gif", "jpg", "jpeg", "heic",
        "mp4", "mov", "m4v",
        "txt", "json", "xml", "pdf"
    ]

    private var allFiles: [SavedSectionFile] {
        groups.flatMap { $0.files }
    }

    private var imageFiles: [SavedSectionFile] {
        allFiles.filter { SavedFileFilter.images.matches($0.url) }
    }

    private var videoFiles: [SavedSectionFile] {
        allFiles.filter { SavedFileFilter.videos.matches($0.url) }
    }

    private var documentFiles: [SavedSectionFile] {
        allFiles.filter { SavedFileFilter.documents.matches($0.url) }
    }

    private var totalBytes: Int64 {
        allFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var imageBytes: Int64 {
        imageFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var videoBytes: Int64 {
        videoFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var documentBytes: Int64 {
        documentFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var filteredGroups: [SavedFileGroup] {
        groups.compactMap { group in
            let query = searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let files = group.files.filter { file in
                let matchesSearch =
                    query.isEmpty ||
                    file.url.lastPathComponent.localizedCaseInsensitiveContains(query) ||
                    group.gameName.localizedCaseInsensitiveContains(query)

                return selectedFilter.matches(file.url) && matchesSearch
            }

            guard !files.isEmpty else {
                return nil
            }

            let sortedFiles = files.sorted { first, second in
                switch selectedSort {
                case .nameAscending:
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(
                        second.url.lastPathComponent
                    ) == .orderedAscending

                case .nameDescending:
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(
                        second.url.lastPathComponent
                    ) == .orderedDescending

                case .newest:
                    return first.creationDate > second.creationDate

                case .largest:
                    return first.sizeBytes > second.sizeBytes
                }
            }

            return SavedFileGroup(
                id: group.id,
                gameName: group.gameName,
                files: sortedFiles
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Saved Section Files",
                        systemImage: "folder",
                        description: Text(
                            "Supported saved files will appear here."
                        )
                    )
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            dashboard
                        }
                        .frame(maxHeight: 250)

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            TextField(
                                "Search files or games",
                                text: $searchText
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .padding(.top, 10)

                        Picker("File Type", selection: $selectedFilter) {
                            ForEach(SavedFileFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 10)

                        HStack {
                            Text("Sort by")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Menu {
                                Picker("Sort by", selection: $selectedSort) {
                                    ForEach(SavedFileSort.allCases) { sort in
                                        Text(sort.title).tag(sort)
                                    }
                                }
                            } label: {
                                Label(
                                    selectedSort.title,
                                    systemImage: "arrow.up.arrow.down"
                                )
                                .font(.subheadline)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if filteredGroups.isEmpty {
                            ContentUnavailableView(
                                "No Matching Files",
                                systemImage: "magnifyingglass",
                                description: Text(
                                    "Try another search or file category."
                                )
                            )
                        } else {
                            List {
                                ForEach(filteredGroups) { group in
                                    Section(group.gameName) {
                                        ForEach(group.files) { file in
                                            fileRow(file, gameName: group.gameName)
                                        }
                                    }
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

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Dashboard")
                .font(.headline)

            HStack(spacing: 12) {
                dashboardCard(
                    title: "Saved Files",
                    value: "\(allFiles.count)",
                    subtitle: "Total files",
                    symbol: "doc.on.doc"
                )

                dashboardCard(
                    title: "Storage Used",
                    value: ByteCountFormatter.string(
                        fromByteCount: totalBytes,
                        countStyle: .file
                    ),
                    subtitle: "Combined size",
                    symbol: "internaldrive"
                )
            }

            Text("By Category")
                .font(.subheadline.weight(.semibold))

            categoryRow(
                title: "Images",
                count: imageFiles.count,
                bytes: imageBytes,
                symbol: "photo"
            )

            categoryRow(
                title: "Videos",
                count: videoFiles.count,
                bytes: videoBytes,
                symbol: "video"
            )

            categoryRow(
                title: "Documents",
                count: documentFiles.count,
                bytes: documentBytes,
                symbol: "doc.text"
            )
        }
        .padding()
    }

    private func dashboardCard(
        title: String,
        value: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryRow(
        title: String,
        count: Int,
        bytes: Int64,
        symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            Text(title)

            Text("(\(count))")
                .foregroundStyle(.secondary)

            Spacer()

            Text(
                ByteCountFormatter.string(
                    fromByteCount: bytes,
                    countStyle: .file
                )
            )
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .font(.subheadline)
    }

    private func fileRow(
        _ file: SavedSectionFile,
        gameName: String
    ) -> some View {
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
                            gameName: gameName
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
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .creationDateKey
                    ],
                    options: [.skipsHiddenFiles]
                )

                let savedFiles = contents.compactMap {
                    url -> SavedSectionFile? in

                    let ext = url.pathExtension.lowercased()

                    guard supportedExtensions.contains(ext) else {
                        return nil
                    }

                    let attributes = try? FileManager.default.attributesOfItem(
                        atPath: url.path
                    )

                    let bytes = (
                        attributes?[.size] as? NSNumber
                    )?.int64Value ?? 0

                    let creationDate = (
                        attributes?[.creationDate] as? Date
                    ) ?? .distantPast

                    return SavedSectionFile(
                        url: url,
                        sizeBytes: bytes,
                        creationDate: creationDate
                    )
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

    var body: some View {
        List {
            Section("File") {
                detailRow("File name", value: url.lastPathComponent)

                detailRow(
                    "Format",
                    value: SavedSectionFile.formatName(for: url)
                )

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
                    Label(
                        "Share This File",
                        systemImage: "square.and.arrow.up"
                    )
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
        case "txt": return "text.alignleft"
        case "json": return "curlybraces"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "pdf": return "doc.richtext"
        case "mp4", "mov", "m4v": return "video"
        default: return "doc"
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
    let sizeBytes: Int64
    let creationDate: Date

    var id: String { url.path }

    var size: String {
        ByteCountFormatter.string(
            fromByteCount: sizeBytes,
            countStyle: .file
        )
    }

    var format: String {
        Self.formatName(for: url)
    }

    static func formatName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        case "jpg", "jpeg": return "JPEG Image"
        case "heic": return "HEIC Image"
        case "mp4": return "MP4 Video"
        case "mov": return "MOV Video"
        case "m4v": return "M4V Video"
        case "txt": return "Text File"
        case "json": return "JSON Data"
        case "xml": return "XML Document"
        case "pdf": return "PDF Document"
        default: return "File"
        }
    }
}

private struct PreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct FileDetailItem: Identifiable {
    let url: URL
    let gameName: String
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
