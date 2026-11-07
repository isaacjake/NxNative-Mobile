private func filesystemName(_ value: UInt8) -> String {
    switch value {
    case 0:
        return "PartitionFS"
    case 1:
        return "RomFS"
    default:
        return "Unknown"
    }
}

private func hashName(_ value: UInt8) -> String {
    switch value {
    case 0:
        return "Auto"
    case 2:
        return "Hierarchical SHA-256"
    case 3:
        return "Hierarchical Integrity"
    default:
        return "Unknown"
    }
}

private func encryptionName(_ value: UInt8) -> String {
    switch value {
    case 0:
        return "Auto"
    case 1:
        return "None"
    case 2:
        return "AES-XTS"
    case 3:
        return "AES-CTR"
    case 4:
        return "BKTR"
    default:
        return "Unknown"
    }
}
