import SwiftUI
import UniformTypeIdentifiers

enum BuildQueueLimits {
    static let maximumJobs = 8
    static let maximumProjectFiles = 10_000
    static let maximumProjectBytes: Int64 = 512 * 1024 * 1024
    static let minimumFreeDiskMB = 512
    static let minimumAvailableMemoryMB = 400
}

enum BuildQueueState: String {
    case queued = "Queued"
    case validating = "Checking project"
    case building = "Building"
    case completed = "Complete"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

struct BuildQueueEntry: Identifiable {
    let id: UUID
    let title: String
    let sourceFolder: URL?
    var state: BuildQueueState = .queued
    var progress = 0.0
    var detail: String
    var outputURL: URL?

    init(title: String, sourceFolder: URL? = nil, detail: String = "Waiting to start") {
        id = UUID()
        self.title = title
        self.sourceFolder = sourceFolder
        self.detail = detail
    }
}

/// A future compiler can supply stages for a selected homebrew or personal test project.
/// The queue itself has no game archive, key, or decryption APIs.
typealias ProjectBuildStageFactory = (URL) -> [BuildStage]?

private enum BuildQueueError: LocalizedError {
    case queueFull
    case folderRequired
    case alreadyQueued
    case compilerUnavailable

    var errorDescription: String? {
        switch self {
        case .queueFull:
            return "The queue is full. Finish or remove a job before adding another."
        case .folderRequired:
            return "Choose a project folder."
        case .alreadyQueued:
            return "That project folder is already queued."
        case .compilerUnavailable:
            return "The homebrew/test-project compiler is not connected yet. This project remains queued."
        }
    }
}

@MainActor
final class BuildQueueController: ObservableObject {
    @Published private(set) var jobs: [BuildQueueEntry] = []

    private let projectStageFactory: ProjectBuildStageFactory?
    private var worker: Task<Void, Never>?
    private var activeJobID: UUID?

    init(projectStageFactory: ProjectBuildStageFactory? = nil) {
        self.projectStageFactory = projectStageFactory
    }

    var isRunning: Bool { activeJobID != nil }
    var canCompileProjects: Bool { projectStageFactory != nil }
    var remainingCapacity: Int {
        max(0, BuildQueueLimits.maximumJobs - jobs.filter { !$0.state.isTerminal }.count)
    }
    var canStart: Bool { worker == nil && nextRunnableIndex != nil }

    private var nextRunnableIndex: Int? {
        jobs.firstIndex { entry in
            guard entry.state == .queued else { return false }
            return entry.sourceFolder == nil || projectStageFactory != nil
        }
    }

    func enqueueHandoffTest() throws {
        try requireCapacity()
        jobs.append(BuildQueueEntry(
            title: "Safe IPA handoff test",
            detail: "Packages a renamed copy of this app; no game files are used"
        ))
    }

    func enqueueProjectFolder(_ folder: URL) throws {
        try requireCapacity()
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { folder.stopAccessingSecurityScopedResource() }
        }
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw BuildQueueError.folderRequired }
        guard !jobs.contains(where: {
            $0.sourceFolder?.standardizedFileURL == folder.standardizedFileURL && !$0.state.isTerminal
        }) else {
            throw BuildQueueError.alreadyQueued
        }

        jobs.append(BuildQueueEntry(
            title: folder.lastPathComponent,
            sourceFolder: folder,
            detail: projectStageFactory == nil
                ? "Waiting for a homebrew/test-project compiler to be connected"
                : "Waiting to start"
        ))
    }

    func start() {
        guard canStart else { return }
        worker = Task { [weak self] in
            await self?.runQueue()
        }
    }

    func cancel(_ entry: BuildQueueEntry) {
        guard let index = jobs.firstIndex(where: { $0.id == entry.id }) else { return }
        if entry.id == activeJobID {
            jobs[index].detail = "Stopping safely…"
            worker?.cancel()
        } else if jobs[index].state == .queued {
            jobs[index].state = .cancelled
            jobs[index].detail = "Cancelled before starting"
        }
    }

    func cancelActiveForBackground() {
        guard let activeJobID,
              let index = jobs.firstIndex(where: { $0.id == activeJobID }) else { return }
        jobs[index].detail = "Stopping because the app went to the background"
        worker?.cancel()
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
    }

    private func requireCapacity() throws {
        guard remainingCapacity > 0 else { throw BuildQueueError.queueFull }
    }

    private func runQueue() async {
        defer {
            activeJobID = nil
            worker = nil
        }

        while !Task.isCancelled, let index = nextRunnableIndex {
            let entry = jobs[index]
            activeJobID = entry.id
            jobs[index].state = .validating
            jobs[index].detail = "Checking project bounds"

            let hasAccess = entry.sourceFolder?.startAccessingSecurityScopedResource() ?? false
            defer {
                if hasAccess, let sourceFolder = entry.sourceFolder {
                    sourceFolder.stopAccessingSecurityScopedResource()
                }
            }

            do {
                if let sourceFolder = entry.sourceFolder {
                    try await Self.validateProjectFolder(sourceFolder)
                }
                try Task.checkCancellation()

                let stages: [BuildStage]
                if let sourceFolder = entry.sourceFolder {
                    guard let projectStageFactory,
                          let projectStages = projectStageFactory(sourceFolder),
                          !projectStages.isEmpty else {
                        throw BuildQueueError.compilerUnavailable
                    }
                    stages = projectStages
                } else {
                    stages = [HandoffTestStage()]
                }

                guard let currentIndex = jobs.firstIndex(where: { $0.id == entry.id }) else { continue }
                jobs[currentIndex].state = .building
                jobs[currentIndex].progress = 0
                jobs[currentIndex].detail = "Preparing one build job"

                let pipelineJob = BuildJob()
                let output = try await pipelineJob.run(
                    stages: stages,
                    sourceFolder: entry.sourceFolder
                ) { [weak self] stage, fraction in
                    Task { @MainActor in
                        self?.updateProgress(jobID: entry.id, stage: stage, fraction: fraction)
                    }
                }

                if let finished = jobs.firstIndex(where: { $0.id == entry.id }) {
                    jobs[finished].state = .completed
                    jobs[finished].progress = 1
                    jobs[finished].detail = "Unsigned IPA ready to share"
                    jobs[finished].outputURL = output
                }
            } catch is CancellationError {
                if let cancelled = jobs.firstIndex(where: { $0.id == entry.id }) {
                    jobs[cancelled].state = .cancelled
                    jobs[cancelled].detail = "Build cancelled; temporary files were cleaned up"
                }
            } catch {
                if let failed = jobs.firstIndex(where: { $0.id == entry.id }) {
                    jobs[failed].state = .failed
                    jobs[failed].detail = error.localizedDescription
                }
            }

            activeJobID = nil
            if Task.isCancelled { break }
        }
    }

    private func updateProgress(jobID: UUID, stage: String, fraction: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].state == .building else { return }
        jobs[index].progress = min(1, max(0, fraction))
        jobs[index].detail = stage
    }

    private nonisolated static func validateProjectFolder(_ folder: URL) async throws {
        let scan = Task.detached(priority: .utility) {
            try ProjectFolderValidator.scan(folder)
        }
        try await withTaskCancellationHandler {
            try await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

}

private enum ProjectFolderValidator {
    static func scan(_ folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw BuildQueueError.folderRequired }
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let file = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey
            ])
            guard file.isSymbolicLink != true else {
                enumerator.skipDescendants()
                continue
            }
            guard file.isRegularFile == true else { continue }

            fileCount += 1
            guard fileCount <= BuildQueueLimits.maximumProjectFiles else {
                throw FolderLimitError.tooManyFiles
            }
            let fileBytes = Int64(max(0, file.fileSize ?? 0))
            guard fileBytes <= BuildQueueLimits.maximumProjectBytes - totalBytes else {
                throw FolderLimitError.projectTooLarge
            }
            totalBytes += fileBytes
        }
    }

    enum FolderLimitError: LocalizedError {
        case tooManyFiles
        case projectTooLarge

        var errorDescription: String? {
            switch self {
            case .tooManyFiles:
                return "This project exceeds the 10,000 file limit."
            case .projectTooLarge:
                return "This project exceeds the 512 MB source limit."
            }
        }
    }
}

struct BuildQueueView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var queue: BuildQueueController
    @State private var showingProjectPicker = false
    @State private var errorMessage: String?

@MainActor
    init(controller: BuildQueueController? = nil) {
        _queue = StateObject(wrappedValue: controller ?? BuildQueueController())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Homebrew and personal test projects", systemImage: "hammer.fill")
                        .font(.headline)
                    Text("This queue accepts project folders and a safe IPA handoff test. It does not accept game archives or key files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !queue.canCompileProjects {
                        Label("The project compiler is not connected. Selected project folders stay queued; the handoff test can still run.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    Text("One build at a time · up to 8 jobs · 10,000 files / 512 MB per project · 512 MB free storage required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("The queue stays in memory for this app session. An active build is cancelled when the app moves to the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Safe build pipeline")
                }

                Section {
                    Button {
                        do { try queue.enqueueHandoffTest() }
                        catch { errorMessage = error.localizedDescription }
                    } label: {
                        Label("Queue IPA handoff test", systemImage: "shippingbox")
                    }
                    .disabled(queue.remainingCapacity == 0)

                    Button {
                        showingProjectPicker = true
                    } label: {
                        Label("Add homebrew or test project folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(queue.remainingCapacity == 0)

                    Button {
                        queue.start()
                    } label: {
                        Label("Start Queue", systemImage: "play.fill")
                    }
                    .disabled(!queue.canStart)

                    if queue.jobs.contains(where: { $0.state.isTerminal }) {
                        Button("Clear Finished Jobs", systemImage: "trash") {
                            queue.clearFinished()
                        }
                    }
                }

                Section("Queue · \(queue.jobs.count)") {
                    if queue.jobs.isEmpty {
                        ContentUnavailableView(
                            "Queue is empty",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Add a safe handoff test or a supported project folder.")
                        )
                    } else {
                        ForEach(queue.jobs) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(entry.state.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(stateColor(entry.state))
                                    }
                                    Spacer()
                                    if !entry.state.isTerminal {
                                        Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
                                            queue.cancel(entry)
                                        }
                                        .labelStyle(.iconOnly)
                                        .accessibilityLabel("Cancel \(entry.title)")
                                    }
                                }

                                if entry.state == .building || entry.state == .validating {
                                    ProgressView(value: entry.progress)
                                }

                                if let outputURL = entry.outputURL {
                                    ShareLink(item: outputURL) {
                                        Label("Share unsigned IPA", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Build Queue")
            .fileImporter(
                isPresented: $showingProjectPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let folder = urls.first else { return }
                    do { try queue.enqueueProjectFolder(folder) }
                    catch { errorMessage = error.localizedDescription }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Could Not Add Project", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please choose a project folder.")
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    queue.cancelActiveForBackground()
                }
            }
        }
    }

    private func stateColor(_ state: BuildQueueState) -> Color {
        switch state {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        case .queued, .validating, .building:
            return .cyan
        }
    }
}
