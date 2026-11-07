
import Foundation

struct GameFileInspection {
    let isRecognized: Bool
    let format: String
    let message: String
}

enum GameFileInspector {

    static func inspect(_ url: URL) -> GameFileInspection {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return GameFileInspection(
                isRecognized: false,
                format: "Unknown",
                message: "File does not exist."
            )
        }

        do {
            let attributes = try fileManager.attributesOfItem(
                atPath: url.path
            )

            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            guard fileSize >= 4 else {
                return GameFileInspection(
                    isRecognized: false,
                    format: "Unknown",
                    message: "File is too small to contain a valid header."
                )
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            // NSP files commonly use a PFS0 container.
            let beginning = try handle.read(upToCount: 4) ?? Data()

            if beginning == Data("PFS0".utf8) {
                return GameFileInspection(
                    isRecognized: true,
                    format: "NSP / PFS0",
                    message: "Recognized PFS0 container header."
                )
            }

            // XCI files contain the HEAD signature at offset 0x100.
            if fileSize >= 0x104 {
                try handle.seek(toOffset: 0x100)
                let xciHeader = try handle.read(upToCount: 4) ?? Data()

                if xciHeader == Data("HEAD".utf8) {
                    return GameFileInspection(
                        isRecognized: true,
                        format: "XCI",
                        message: "Recognized XCI header."
                    )
                }
            }

            return GameFileInspection(
                isRecognized: false,
                format: "Unknown",
                message: "No recognized NSP or XCI header was found."
            )

        } catch {
            return GameFileInspection(
                isRecognized: false,
                format: "Error",
                message: error.localizedDescription
            )
        }
    }
}
