import Foundation

/// Streams the user's home directory looking for individual files at or above a
/// configurable size threshold. The walker is deliberately conservative:
///
/// - Skips hidden files (`.skipsHiddenFiles`)
/// - Skips package descendants so `.app` bundles don't surface their internals
/// - Skips symbolic links to avoid following loops out of `~`
/// - Skips `~/Library` by default (system-managed caches we already cover in Smart Clean)
///
/// The work is performed synchronously inside an actor task. `FileManager.enumerator`
/// is itself a streaming iterator, so memory stays bounded regardless of how many
/// files exist under the root.
actor LargeFileFinder {
    private let fileManager = FileManager.default

    /// Default subpaths inside the home dir that produce too much noise to be useful
    /// in a "find my big files" view. Caches under `~/Library` are surfaced via
    /// Smart Clean, and `~/.Trash` is intentionally excluded so users don't see
    /// already-deleted files reported back to them.
    private static let defaultExcludedSubpaths: [String] = [
        "/Library",
        "/.Trash",
        "/.cache",
    ]

    /// Walk `rootPath` and return every regular file whose size is `>= minimumSize`,
    /// sorted by size descending.
    ///
    /// `progressHandler` is invoked on the main actor every 500 files visited so the
    /// UI can show a live "X files checked" counter without thrashing.
    func scan(
        rootPath: String = NSHomeDirectory(),
        minimumSize: Int64 = 100 * 1024 * 1024,
        progressHandler: @MainActor @escaping (Int) -> Void
    ) async -> [LargeFile] {
        let root = URL(fileURLWithPath: rootPath)
        let excluded = Self.defaultExcludedSubpaths.map { rootPath + $0 }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey,
                .isRegularFileKey,
                .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }  // best-effort: ignore unreadable paths
        ) else {
            return []
        }

        var results: [LargeFile] = []
        var visited = 0

        while let next = enumerator.nextObject() as? URL {
            // Periodically check for cancellation so the user can rescan / leave the view.
            if Task.isCancelled { break }

            // Skip excluded subtrees by pruning the enumerator's descent.
            if excluded.contains(where: { next.path.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }

            visited += 1
            if visited % 500 == 0 {
                let count = visited
                await MainActor.run { progressHandler(count) }
            }

            guard let values = try? next.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey,
                .isRegularFileKey,
            ]) else { continue }

            if values.isSymbolicLink == true { continue }
            if values.isRegularFile != true { continue }

            let size = Int64(values.fileSize ?? 0)
            guard size >= minimumSize else { continue }

            let kind = LargeFileKind.classify(extension: next.pathExtension)
            results.append(LargeFile(
                url: next,
                size: size,
                modifiedDate: values.contentModificationDate,
                kind: kind
            ))
        }

        // One final tick so the UI ends on the true total.
        let final = visited
        await MainActor.run { progressHandler(final) }

        results.sort { $0.size > $1.size }
        return results
    }

    /// Move the given files to the user's Trash. Recoverable, never permadelete.
    /// Returns total bytes freed (sum of successfully trashed file sizes) and any errors.
    func delete(_ files: [LargeFile]) async -> (bytesFreed: Int64, errors: [FileCleanupError]) {
        var freed: Int64 = 0
        var errors: [FileCleanupError] = []

        for file in files {
            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                freed += file.size
            } catch {
                errors.append(FileCleanupError(
                    path: file.url.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        return (freed, errors)
    }
}
