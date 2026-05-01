import Foundation

/// Strategy for auto-selecting which copies to delete in a duplicate group.
/// One copy ALWAYS remains regardless of strategy.
enum KeepStrategy: String, CaseIterable, Hashable, Sendable {
    case keepNewest = "Keep newest"
    case keepOldest = "Keep oldest"
    case keepShortestPath = "Keep shortest path"

    var symbol: String {
        switch self {
        case .keepNewest: return "clock.arrow.circlepath"
        case .keepOldest: return "clock.badge.checkmark"
        case .keepShortestPath: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

/// A pre-resolved duplicate copy with its size and modification date. We carry
/// these on the group so we don't re-stat URLs in the UI layer.
struct DuplicateFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let modifiedDate: Date?

    init(url: URL, modifiedDate: Date?) {
        self.id = UUID()
        self.url = url
        self.modifiedDate = modifiedDate
    }

    var displayPath: String {
        let path = url.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}

/// A group of files with identical content (same size + same SHA-256). The first
/// element is treated as the "canonical" copy for display purposes; auto-select
/// strategies don't depend on order.
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let hash: String
    let size: Int64
    let files: [DuplicateFile]

    init(hash: String, size: Int64, files: [DuplicateFile]) {
        self.id = UUID()
        self.hash = hash
        self.size = size
        self.files = files
    }

    /// Bytes that would be reclaimed if all but one copy were removed.
    var wastedBytes: Int64 { size * Int64(max(files.count - 1, 0)) }

    var representativeName: String {
        files.first?.url.lastPathComponent ?? "Unknown"
    }

    /// Returns URLs to delete given a keep strategy. The "winner" (the file to
    /// keep) is chosen per the strategy; everything else is returned for deletion.
    func urlsToDelete(strategy: KeepStrategy) -> [URL] {
        guard files.count > 1 else { return [] }
        guard let winner = winner(for: strategy) else { return [] }
        return files.compactMap { $0.id == winner.id ? nil : $0.url }
    }

    func winner(for strategy: KeepStrategy) -> DuplicateFile? {
        switch strategy {
        case .keepNewest:
            return files.max { lhs, rhs in
                (lhs.modifiedDate ?? .distantPast) < (rhs.modifiedDate ?? .distantPast)
            }
        case .keepOldest:
            return files.min { lhs, rhs in
                (lhs.modifiedDate ?? .distantFuture) < (rhs.modifiedDate ?? .distantFuture)
            }
        case .keepShortestPath:
            return files.min { lhs, rhs in
                lhs.url.path.count < rhs.url.path.count
            }
        }
    }
}
