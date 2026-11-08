
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
        case .all: return true
        case .images: return ["png", "gif", "jpg", "jpeg", "heic"].contains(ext)
        case .videos: return ["mp4", "mov", "m4v"].contains(ext)
        case .documents: return ["pdf", "txt", "json", "xml"].contains(ext)
        }
    }
}

private enum SavedFileSort: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, newest, largest

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

    @State private var isSelectionMode = false
    @State private var selectedFileIDs: Set<String> = []
    @State private var isBulkDeleteConfirmationPresented = false

    private let supportedExtensions: Set<String> = [
        "png", "gif", "jpg", "jpeg", "heic",
        "mp4", "mov", "m4v", "txt", "json", "xml", "pdf"
    ]

    private var allFiles: [SavedSectionFile] {
        groups.flatMap { $0.files }
    }

    private var selectedFiles: [SavedSectionFile] {
        allFiles.filter { selectedFileIDs.contains($0.id) }
    }

    private func files(for filter: SavedFileFilter) -> [SavedSectionFile] {
        allFiles.filter { filter.matches($0.url) }
    }

    private func bytes(for files: [SavedSectionFile]) -> Int64 {
        files.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var imageFiles: [SavedSectionFile] { files(for: .images) }
    private var videoFiles: [SavedSectionFile] { files(for: .videos) }
    private var documentFiles: [SavedSectionFile] { files(for: .documents) }
    private var totalBytes: Int64 { bytes(for: allFiles) }

    private var filteredGroups: [SavedFileGroup] {
        groups.compactMap { group in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            let matching = group.files.filter { file in
                let matchesSearch = query.isEmpty ||
                    file.url.lastPathComponent.localizedCaseInsensitiveContains(query) ||
                    group.gameName.localizedCaseInsensitiveContains(query)

                return selectedFilter.matches(file.url) && matchesSearch
            }

            guard !matching.isEmpty else { return nil }

            let sorted = matching.sorted { first, second in
                switch selectedSort {
                case .nameAscending:
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(second.url.lastPathComponent) == .orderedAscending
                case .nameDescending:
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(second.url.lastPathComponent) == .orderedDescending
                case .newest:
                    return first.creationDate > second.creationDate
                case .largest:
                    return first.sizeBytes > second.sizeBytes
                }
            }

            return SavedFileGroup(
                id: group.id,
                gameName: group.gameName,
                files: sorted
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
                        description: Text("Supported saved files will appear here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            dashboard
                        }
                        .frame(maxHeight: 390)

                        searchBar

                        Picker("File Type", selection: $selectedFilter) {
                            ForEach(SavedFileFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 10)

                        sortMenu

                        if isSelectionMode {
                            HStack {
                                Text("\(selectedFileIDs.count) selected")
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Button("Select All") {
                                    selectAllVisibleFiles()
                                }
                                .font(.subheadline)

                                Button("Clear") {
                                    selectedFileIDs.removeAll()
                                }
                                .font(.subheadline)
                                .disabled(selectedFileIDs.isEmpty)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }

                        if filteredGroups.isEmpty {
                            ContentUnavailableView(
                                "No Matching Files",
                                systemImage: "magnifyingglass",
                                description: Text("Try another search or file category.")
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        loadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh saved files")

                    if !allFiles.isEmpty {
                        Button(isSelectionMode ? "Cancel" : "Select") {
                            toggleSelectionMode()
                        }
                    }

                    if isSelectionMode && !selectedFileIDs.isEmpty {
                        Button(role: .destructive) {
                            isBulkDeleteConfirmationPresented = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete selected files")
                    }
                }
            }
            .onAppear { loadFiles() }
            .sheet(item: $previewItem) { item in
                NavigationStack {
                    QuickLookPreviewController(url: item.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(item.url.lastPathComponent)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { previewItem = nil }
                            }
                        }
                }
            }
            .sheet(item: $detailItem) { item in
                NavigationStack {
                    FileDetailsView(url: item.url, gameName: item.gameName)
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
                Text("This removes the saved copy from NxNative. Your original NSP or XCI game file will not be affected.")
            }
            .confirmationDialog(
                "Delete \(selectedFileIDs.count) Saved Files?",
                isPresented: $isBulkDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete \(selectedFileIDs.count) Files", role: .destructive) {
                    deleteSelectedFiles()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only the selected saved copies will be deleted. Original NSP and XCI files will not be affected.")
            }
            .alert(
                "File Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func toggleSelectionMode() {
        isSelectionMode.toggle()

        if !isSelectionMode {
            selectedFileIDs.removeAll()
        }
    }

    private func selectAllVisibleFiles() {
        for group in filteredGroups {
            for file in group.files {
                selectedFileIDs.insert(file.id)
            }
        }
    }

    private func toggleFileSelection(_ file: SavedSectionFile) {
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
        } else {
            selectedFileIDs.insert(file.id)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search files or games", text: $searchText)
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
    }

    private var sortMenu: some View {
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
                Label(selectedSort.title, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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
                    value: formattedBytes(totalBytes),
                    subtitle: "Combined size",
                    symbol: "internaldrive"
                )
            }

            Text("By Category")
                .font(.subheadline.weight(.semibold))

            categoryRow(title: "Images", count: imageFiles.count, bytes: bytes(for: imageFiles), symbol: "photo")
            categoryRow(title: "Videos", count: videoFiles.count, bytes: bytes(for: videoFiles), symbol: "video")
            categoryRow(title: "Documents", count: documentFiles.count, bytes: bytes(for: documentFiles), symbol: "doc.text")

            Divider()

            HStack {
                Text("Storage by Game")
                    .font(.headline)

                Spacer()

                Text("\(groups.count) games")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(groups) { group in
                gameStorageRow(group)
            }
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

            Text(formattedBytes(bytes))
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .font(.subheadline)
    }

    private func gameStorageRow(_ group: SavedFileGroup) -> some View {
        let count = group.files.count
        let size = group.files.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let percentage = totalBytes > 0
            ? min(1.0, Double(size) / Double(totalBytes))
            : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(group.gameName, systemImage: "gamecontroller")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(formattedBytes(size))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 7)

            Text("\(count) saved \(count == 1 ? "file" : "files")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func fileRow(
        _ file: SavedSectionFile,
        gameName: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectionMode {
                Button {
                    toggleFileSelection(file)
                } label: {
                    Image(
                        systemName: selectedFileIDs.contains(file.id)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        selectedFileIDs.contains(file.id)
                            ? Color.accentColor
                            : Color.secondary
                    )
                    .frame(width: 28, height: 76)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    selectedFileIDs.contains(file.id)
                        ? "Deselect file"
                        : "Select file"
                )
            }

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
                        detailItem = FileDetailItem(url: file.url, gameName: gameName)
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
                selectedFileIDs.removeAll()
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
                let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }

                let contents = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
                    options: [.skipsHiddenFiles]
                )

                let savedFiles = contents.compactMap { url -> SavedSectionFile? in
                    let ext = url.pathExtension.lowercased()
                    guard supportedExtensions.contains(ext) else { return nil }

                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                    let date = (attributes?[.creationDate] as? Date) ?? .distantPast

                    return SavedSectionFile(
                        url: url,
                        sizeBytes: size,
                        creationDate: date
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
                $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending
            }

            let existingIDs = Set(allFiles.map { $0.id })
            selectedFileIDs.formIntersection(existingIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingFile() {
        guard let file = pendingDelete else { return }

        do {
            try FileManager.default.removeItem(at: file.url)
            selectedFileIDs.remove(file.id)
            pendingDelete = nil
            loadFiles()
        } catch {
            pendingDelete = nil
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedFiles() {
        let filesToDelete = selectedFiles
        var failures: [String] = []

        for file in filesToDelete {
            do {
                try FileManager.default.removeItem(at: file.url)
            } catch {
                failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        selectedFileIDs.removeAll()
        isSelectionMode = false
        loadFiles()

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }
}

private struct FileDetailsView: View {
    let url: URL
    let gameName: String

    @Environment(\.dismiss) private var dismiss

    private var fileBytes: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    var body: some View {
        List {
            Section("File") {
                detailRow("File name", value: url.lastPathComponent)
                detailRow("Format", value: SavedSectionFile.formatName(for: url))
                detailRow(
                    "Size",
                    value: ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file)
                )
                detailRow("Exact size", value: "\(fileBytes) bytes")
            }

            Section("Game") {
                detailRow("Game name", value: gameName)
            }

            Section("Storage") {
                detailRow("Folder", value: url.deletingLastPathComponent().lastPathComponent)
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
                Button("Done") { dismiss() }
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
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
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

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
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
