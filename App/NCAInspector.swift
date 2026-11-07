import Foundation
struct NCAInspection {
    let isRecognized: Bool
    let magic: String
    let contentType: UInt8?
    let cryptoType: UInt8?
    let keyGeneration: UInt8?
    let fileSize: UInt64
    let message: String
}
enum NCAInspector {
    static func inspect(_ url: URL) -> NCAInspection {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard fileSize >= 0x204 else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize, "File is too small for an NCA header."
                )
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: 0x200)
            guard let header = try handle.read(upToCount: 8),
                  header.count == 8 else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize, "Could not read the NCA header."
                )
            }
            let magicData = header.prefix(4)
            guard let magic = String(
                data: magicData,
                encoding: .ascii
            ), ["NCA0", "NCA2", "NCA3"].contains(magic) else {
                return result(
                    false, "Unknown", nil, nil, nil,
                    fileSize, "No recognized NCA signature was found."
                )
            }
            return result(
                true,
                magic,
                header[5],
                header[6],
                header[7],
                fileSize,
                "NCA header signature recognized. This does not mean the file is decrypted."
            )
        } catch {
            return result(
                false, "Error", nil, nil, nil,
                0, error.localizedDescription
            )
        }
    }
    private static func result(
        _ recognized: Bool,
        _ magic: String,
        _ contentType: UInt8?,
        _ cryptoType: UInt8?,
        _ keyGeneration: UInt8?,
        _ fileSize: UInt64,
        _ message: String
    ) -> NCAInspection {
        NCAInspection(
            isRecognized: recognized,
            magic: magic,
            contentType: contentType,
            cryptoType: cryptoType,
            keyGeneration: keyGeneration,
            fileSize: fileSize,
            message: message
        )
    }
}
