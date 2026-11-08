import Foundation
import os

// MARK: - Resource guard

/// Call from inside long-running stages (e.g. once per chunk of work) to avoid
/// getting killed by iOS for memory, or cooking the phone.
enum ResourceGuard {
    enum Problem: LocalizedError {
        case lowMemory(availableMB: Int)
        case lowDisk(availableMB: Int, neededMB: Int)
        case overheating

        var errorDescription: String? {
            switch self {
            case let .lowMemory(mb):
                return "Not enough free memory (\(mb) MB available). Close other apps and try again."
            case let .lowDisk(avail, needed):
                return "Not enough free storage (\(avail) MB free, about \(needed) MB needed)."
            case .overheating:
                return "The device is too hot. Let it cool down, then resume."
            }
        }
    }

    /// Memory iOS will still let this app allocate before it is terminated.
    static var availableMemoryMB: Int {
        Int(os_proc_available_memory()) / 1_048_576
    }

    static func checkMemory(minimumMB: Int = 400) throws {
        let mb = availableMemoryMB
        if mb < minimumMB { throw Problem.lowMemory(availableMB: mb) }
    }

    static func checkDisk(neededMB: Int) throws {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let availMB = Int((values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_048_576)
        if availMB < neededMB { throw Problem.lowDisk(availableMB: availMB, neededMB: neededMB) }
    }

    /// Pauses (up to `maxWait` seconds) while the device is `.serious`, throws on `.critical`.
    /// Call between chunks of work. Respects task cancellation.
    static func waitForThermals(maxWait: TimeInterval = 120) async throws {
        let deadline = Date().addingTimeInterval(maxWait)
        while true {
            try Task.checkCancellation()
            switch ProcessInfo.processInfo.thermalState {
            case .nominal, .fair:
                return
            case .critical:
                throw Problem.overheating
            case .serious:
                if Date() > deadline { throw Problem.overheating }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            @unknown default:
                return
            }
        }
    }

    /// One-call convenience for the top of each chunk.
    static func checkpointGuard(minimumMB: Int = 400) async throws {
        try checkMemory(minimumMB: minimumMB)
        try await waitForThermals()
    }
}

// MARK: - Checkpoints (resume after kill / cancel)

/// Persists which stages of a job finished so a relaunch can resume instead of restarting.
/// Work directories must be kept (not cleaned up) while a job is resumable.
struct JobCheckpoint: Codable {
    var jobKey: String            // stable id, e.g. hash of the input's identifier
    var completedStages: [String]
    var updatedAt: Date
}

enum CheckpointStore {
    private static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("checkpoints.json")
    }

    private static func loadAll() -> [String: JobCheckpoint] {
        guard let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: JobCheckpoint].self, from: data)
        else { return [:] }
        return all
    }

    private static func saveAll(_ all: [String: JobCheckpoint]) {
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(jobKey: String) -> JobCheckpoint? {
        loadAll()[jobKey]
    }

    static func markCompleted(stage: String, jobKey: String) {
        var all = loadAll()
        var cp = all[jobKey] ?? JobCheckpoint(jobKey: jobKey, completedStages: [], updatedAt: Date())
        if !cp.completedStages.contains(stage) { cp.completedStages.append(stage) }
        cp.updatedAt = Date()
        all[jobKey] = cp
        saveAll(all)
    }

    static func clear(jobKey: String) {
        var all = loadAll()
        all.removeValue(forKey: jobKey)
        saveAll(all)
    }
}

// MARK: - Example usage inside a stage

/*
 struct ExampleChunkedStage: BuildStage {
     let name = "Example stage"

     func run(context: BuildContext, report: @Sendable (Double) -> Void) async throws {
         try ResourceGuard.checkDisk(neededMB: 1500)

         let chunkCount = 100                      // however you split your work
         for i in 0..<chunkCount {
             try await ResourceGuard.checkpointGuard()   // memory + thermal + cancellation
             try autoreleasepool { try processChunk(i) } // keep peak memory flat
             report(Double(i + 1) / Double(chunkCount))
         }
     }
 }

 In BuildJob.start, wrap each stage:
     if CheckpointStore.load(jobKey: key)?.completedStages.contains(stage.name) == true { continue }
     ... run stage ...
     CheckpointStore.markCompleted(stage: stage.name, jobKey: key)
 and call CheckpointStore.clear(jobKey:) once the IPA is exported.
 Also stop calling context.cleanUp() on failure/cancel when the job is resumable.
*/
