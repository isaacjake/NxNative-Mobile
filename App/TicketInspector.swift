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
                    message: "Unexpected ticket size. Signature inspection skipped."
                )
            }

            let data = try Data(contentsOf: url)

            guard data.count >= 4 else {
                return TicketInspection(
                    fileSize: fileSize,
                    isRecognized: false,
                    message: "Ticket is too small to inspect."
                )
            }

            let signatureType =
                (UInt32(data[0]) << 24) |
                (UInt32(data[1]) << 16) |
                (UInt32(data[2]) << 8) |
                UInt32(data[3])

            let signatureName: String

            switch signatureType {
            case 0x00010000:
                signatureName = "RSA-4096"
            case 0x00010001:
                signatureName = "RSA-2048"
            case 0x00010002:
                signatureName = "ECDSA"
            default:
                return TicketInspection(
                    fileSize: fileSize,
                    isRecognized: false,
                    message: String(
                        format: "Unknown signature type: 0x%08X. No secret data was read.",
                        signatureType
                    )
                )
            }

            return TicketInspection(
                fileSize: fileSize,
                isRecognized: true,
                message: "Ticket signature type: \(signatureName). Signature metadata inspected; secret key material was not accessed."
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
