Text(
    "Offset: 0x\(String(
        section.offsetBytes,
        radix: 16,
        uppercase: true
    ))"
)
.font(.caption)

let formattedSectionSize = ByteCountFormatter.string(
    fromByteCount: Int64(clamping: section.sizeBytes),
    countStyle: .file
)

Text("Size: \(formattedSectionSize)")
    .font(.caption)
    .foregroundStyle(.secondary)
