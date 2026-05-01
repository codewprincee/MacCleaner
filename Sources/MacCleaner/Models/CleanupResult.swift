import Foundation

struct FileCleanupError: Identifiable, Error, LocalizedError {
    let id = UUID()
    let path: String
    let reason: String

    var errorDescription: String? { "\(path): \(reason)" }
}

struct CleanupResult: Identifiable {
    let id = UUID()
    let type: CleanupType
    let bytesFreed: Int64
    let success: Bool
    let message: String
    let errors: [FileCleanupError]
    let partialSuccess: Bool

    init(type: CleanupType, bytesFreed: Int64, success: Bool, message: String,
         errors: [FileCleanupError] = [], partialSuccess: Bool = false) {
        self.type = type
        self.bytesFreed = bytesFreed
        self.success = success
        self.message = message
        self.errors = errors
        self.partialSuccess = partialSuccess
    }
}

struct CleanupSummary {
    let results: [CleanupResult]
    let totalBytesFreed: Int64
    let diskBefore: DiskUsageInfo?
    let diskAfter: DiskUsageInfo?

    var successCount: Int {
        results.filter { $0.success || $0.partialSuccess }.count
    }

    var failureCount: Int {
        results.filter { !$0.success && !$0.partialSuccess }.count
    }
}
