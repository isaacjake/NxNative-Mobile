import SwiftUI
import UIKit

// MARK: - In-app log buffer

/// Lightweight ring buffer. Call `AppLog.add("message")` anywhere (pipeline stages,
/// import errors, build failures). Never log keys, file contents, or full file paths
/// of user content; log stage names, error descriptions, and sizes only.
enum AppLog {
    private static let queue = DispatchQueue(label: "nxnative.applog")
    private static var lines: [String] = []
    private static let maxLines = 300
    private static let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    static func add(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)"
        queue.sync {
            lines.append(line)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        }
    }

    static func snapshot() -> [String] {
        queue.sync { lines }
    }
}

// MARK: - Report

enum Diagnostics {
    static func buildReport() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        let process = ProcessInfo.processInfo

        var out: [String] = []
        out.append("NxNative diagnostics")
        out.append("Version: \(version) (build \(build))")
        out.append("Device: \(machineIdentifier())")
        out.append("iOS: \(device.systemVersion)")
        out.append("Physical memory: \(format(bytes: Int64(process.physicalMemory)))")
        out.append("Free storage: \(freeStorage())")
        out.append("Thermal state: \(thermalDescription(process.thermalState))")
        out.append("Low Power Mode: \(process.isLowPowerModeEnabled ? "on" : "off")")
        out.append("Bundle ID: \(Bundle.main.bundleIdentifier ?? "?")")
        out.append("")
        out.append("Recent log (\(AppLog.snapshot().count) lines):")
        out.append(contentsOf: AppLog.snapshot())
        return out.joined(separator: "\n")
    }

    /// Writes the report to a temp file so it shares as an attachment.
    static func writeReportFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NxNative-diagnostics.txt")
        try buildReport().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Helpers

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func freeStorage() -> String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return format(bytes: bytes)
        }
        return "unknown"
    }

    private static func thermalDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}

// MARK: - UI

struct DiagnosticsView: View {
    @State private var reportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Creates a text file with your device model, iOS version, memory, storage, and recent app log lines. It contains no keys and no game data. Attach it to your bug report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let reportURL {
                    ShareLink(item: reportURL) {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Generate report") {
                    do {
                        reportURL = try Diagnostics.writeReportFile()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section("Preview") {
                Text(Diagnostics.buildReport())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Diagnostics")
    }
}
