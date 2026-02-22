import Foundation

enum ByteFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }

        let doubleBytes = Double(bytes)
        var unitIndex = 0
        var size = doubleBytes

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }

    static func format(_ bytes: UInt64) -> String {
        format(Int64(min(bytes, UInt64(Int64.max))))
    }
}
