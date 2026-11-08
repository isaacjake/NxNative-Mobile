import SwiftUI
import UniformTypeIdentifiers

// MARK: - Stages

/// One step of the on-device pipeline. Implement concrete stages elsewhere
/// (prepare, compile, link, bundle). Each stage reads/writes inside `context.workDir`.
protocol BuildStage: Sendable {
    var name: String { get }
    func run(context: BuildContext, report: @Sendable (Double) -> Void) async throws
}

/// Shared state passed through the pipeline.
final class BuildContext: @unchecked Sendable {
    let jobID = UUID()
    let workDir: URL
    /// Set by the bundle stage: the finished (unsigned) .app directory.
    var appBundleURL: URL?

    init() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-\(jobID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: workDir)
    }
}

// MARK: - Job

@MainActor
final class BuildJob: ObservableObject {
    enum State: Equatable {
        case idle
        case running(stage: String, progress: Double)
        case finished(ipa: URL)
        case failed(String)
        case cancelled
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func start(stages: [BuildStage]) {
        guard case .idle = state else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let context: BuildContext
            do { context = try BuildContext() } catch {
                state = .failed(error.localizedDescription); return
            }

            do {
                for (index, stage) in stages.enumerated() {
                    try Task.checkCancellation()
                    state = .running(stage: stage.name, progress: Double(index) / Double(stages.count))
                    try await stage.run(context: context) { [weak self] fraction in
                        let overall = (Double(index) + fraction) / Double(stages.count)
                        Task { @MainActor in self?.state = .running(stage: stage.name, progress: overall) }
                    }
                }
                try Task.checkCancellation()
                guard let app = context.appBundleURL else { throw BuildError.noBundleProduced }
                let ipa = try IPAExporter.export(appBundle: app)
                context.cleanUp()
                state = .finished(ipa: ipa)
            } catch is CancellationError {
                context.cleanUp()
                state = .cancelled
            } catch {
                context.cleanUp()
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel() }

    func reset() { task = nil; state = .idle }
}

enum BuildError: LocalizedError {
    case noBundleProduced
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noBundleProduced: return "The build finished but no app bundle was produced."
        case .exportFailed: return "Could not package the app into an .ipa."
        }
    }
}

// MARK: - IPA export

enum IPAExporter {
    /// Wraps `Foo.app` as `Payload/Foo.app`, zips it, and returns a `.ipa` URL
    /// in a stable Documents/Exports folder (so Files/AltStore can reach it).
    /// Output is UNSIGNED on purpose; AltStore re-signs on install.
    static func export(appBundle: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("ipa-\(UUID().uuidString)")
        let payload = staging.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try fm.copyItem(at: appBundle, to: payload.appendingPathComponent(appBundle.lastPathComponent))
        defer { try? fm.removeItem(at: staging) }

        // NSFileCoordinator's .forUploading option zips a directory for us (no zip library needed).
        // VERIFY on device that the archive root is "Payload/" — if it is nested one level
        // deeper, switch to a small zip writer instead.
        var coordError: NSError?
        var zipped: URL?
        NSFileCoordinator().coordinate(readingItemAt: payload, options: .forUploading, error: &coordError) { tempZip in
            let exports = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            let name = appBundle.deletingPathExtension().lastPathComponent + ".ipa"
            let dest = exports.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: tempZip, to: dest)
                zipped = dest
            } catch { zipped = nil }
        }
        if let coordError { throw coordError }
        guard let zipped else { throw BuildError.exportFailed }
        return zipped
    }
}

// MARK: - UI

struct BuildJobView: View {
    @StateObject private var job = BuildJob()
    /// Inject the real stages from your pipeline.
    let stages: [BuildStage]

    var body: some View {
        VStack(spacing: 16) {
            switch job.state {
            case .idle:
                Button("Start Build") { job.start(stages: stages) }
                    .buttonStyle(.borderedProminent)

            case let .running(stage, progress):
                ProgressView(value: progress) { Text(stage) }
                Button("Cancel", role: .cancel) { job.cancel() }

            case let .finished(ipa):
                Label("Build complete", systemImage: "checkmark.circle.fill")
                // Share sheet -> pick AltStore ("Open in AltStore") to sign and install.
                ShareLink(item: ipa) {
                    Label("Send to AltStore", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { job.reset() }

            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try Again") { job.reset() }

            case .cancelled:
                Text("Build cancelled")
                Button("OK") { job.reset() }
            }
        }
        .padding()
    }
}
