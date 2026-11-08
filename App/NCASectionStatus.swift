
import Foundation

extension NCASectionInfo {
    var contentStatus: String {
        switch encryptionType {
        case 1:
            return "Unencrypted — eligible for read-only filesystem inspection"
        case 2:
            return "AES-XTS encrypted — filesystem contents not inspected"
        case 3:
            return "AES-CTR encrypted — filesystem contents not inspected"
        case 4:
            return "BKTR encrypted — filesystem contents not inspected"
        default:
            return "Encryption type unknown — contents not inspected"
        }
    }
}
