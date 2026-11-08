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
                    message: "Unexpected ticket size. Inspection limited."
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
                UInt32(data[0]) |
                (UInt32(data[1]) << 8) |
                (UInt32(data[2]) << 16) |
                (UInt32(data[3]) << 24)

            let signatureName: String

            switch signatureType {
            case 0x00010000:
                signatureName = "RSA-4096 SHA-1"
            case 0x00010001:
                signatureName = "RSA-2048 SHA-1"
            case 0x00010002:
                signatureName = "ECDSA SHA-1"
            case 0x00010003:
                signatureName = "RSA-4096 SHA-256"
            case 0x00010004:
                signatureName = "RSA-2048 SHA-256"
            case 0x00010005:
                signatureName = "ECDSA SHA-256"
            case 0x00010006:
                signatureName = "HMAC-SHA1"
            default:
                return TicketInspection(
                    fileSize: fileSize,
                    isRecognized: false,
                    message: String(
                        format: "Unknown signature type: 0x%08X",
                        signatureType
                    )
                )
            }

            return TicketInspection(
                fileSize: fileSize,
                isRecognized: true,
                message: "Signature metadata: \(signatureName). Secret key material was not accessed."
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
