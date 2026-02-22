import Foundation

struct DiskUsageInfo {
    let totalSpace: Int64
    let freeSpace: Int64

    var usedSpace: Int64 { totalSpace - freeSpace }
    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    static func current() -> DiskUsageInfo? {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else {
            return nil
        }

        guard let totalSize = attributes[.systemSize] as? Int64,
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return nil
        }

        return DiskUsageInfo(totalSpace: totalSize, freeSpace: freeSize)
    }
}
