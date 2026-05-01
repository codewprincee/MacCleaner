import Foundation

struct DiskUsageInfo: Equatable {
    let volumeName: String
    let totalSpace: Int64
    /// Free space as reported by APFS, EXCLUDING purgeable space.
    let freeSpace: Int64
    /// "Available for important usage" — what macOS considers reclaimable + free,
    /// matching the number Finder shows in About This Mac.
    let availableSpace: Int64

    var usedSpace: Int64 { max(totalSpace - availableSpace, 0) }
    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    /// Snapshot the boot volume ("/"), which on macOS is the user's primary drive
    /// regardless of where their home directory lives.
    static func current() -> DiskUsageInfo? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        let available: Int64
        if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
            available = Int64(truncatingIfNeeded: importantUsage)
        } else {
            available = free
        }
        let name = values.volumeName ?? "Macintosh HD"

        guard total > 0 else { return nil }

        return DiskUsageInfo(
            volumeName: name,
            totalSpace: total,
            freeSpace: free,
            availableSpace: available
        )
    }
}
