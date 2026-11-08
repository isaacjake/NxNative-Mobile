import Foundation

struct TicketInspection {
    let fileSize: Int
    let isRecognized: Bool
    let message: String
}

enum TicketInspector {
    static func inspect(_ url: URL) -> TicketInspection {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )

            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0

            guard url.pathExtension.lowercased() == "tik" else {
                return TicketInspection(
                    fileSize: fileSize,
                    isRecognized: false,
                    message: "Not a ticket file."
                )
            }

            guard fileSize == 704 else {
                return TicketInspection(
                    fileSize: fileSize,
                    isRecognized: false,
                    message: "Ticket size is unexpected. Metadata inspection is limited."
                )
            }

            return TicketInspection(
                fileSize: fileSize,
                isRecognized: true,
                message: "Ticket file recognized. Secret key material is not displayed or exported."
            )

        } catch {
            return TicketInspection(
                fileSize: 0,
                isRecognized: false,
                message: "Could not inspect ticket file."
            )
        }
    }
}
