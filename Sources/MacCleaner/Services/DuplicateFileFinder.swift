import Foundation
import CryptoKit

/// Finds files with identical content across user-selected folders using a
/// two-pass algorithm:
///
/// 1. **Size pass.** Walk every folder, group regular files by `fileSize`. Drop
///    every group of size 1 — a file with a unique size cannot be a duplicate.
///    This pass is O(N) and extremely cheap (no hashing).
///
/// 2. **Hash pass.** For each remaining size-group, stream-hash each file with
///    SHA-256 in 1 MB chunks (so we never hold a whole file in RAM). Group by
///    hash and drop hash-groups of size 1.
///
/// On a typical home directory with ~100k files most fall into unique-size buckets
/// after pass 1, so pass 2 only hashes a few thousand candidates. Memory stays
/// bounded — we only keep `(URL, size, mtime)` per file plus per-group buckets.
actor DuplicateFileFinder {
    private let fileManager = FileManager.default

    /// Per-file metadata captured during pass 1.
    private struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    /// Scan `folders`, return groups of files with identical content (size + SHA-256).
    ///
    /// `progressHandler(scanned, totalCandidates)` is called on the main actor:
    /// - During pass 1, `total` is 0 and `scanned` reflects files visited
    /// - During pass 2, `total` is the candidate count and `scanned` is files hashed
    func scan(
        folders: [URL],
        minimumSize: Int64 = 1024 * 1024,
        progressHandler: @MainActor @escaping (Int, Int) -> Void
    ) async -> [DuplicateGroup] {
        // -------------------------------------------------------------
        // Pass 1: size bucketing
        // -------------------------------------------------------------
        var bySize: [Int64: [Candidate]] = [:]
        var visited = 0

        for folder in folders {
            if Task.isCancelled { break }
            await collectCandidates(
                in: folder,
                minimumSize: minimumSize,
                bySize: &bySize,
                visited: &visited,
                progressHandler: progressHandler
            )
        }

        // Drop unique-size buckets — they cannot be duplicates.
        let candidateGroups: [[Candidate]] = bySize.values.filter { $0.count > 1 }
        let totalToHash = candidateGroups.reduce(0) { $0 + $1.count }

        await MainActor.run { progressHandler(0, totalToHash) }

        // -------------------------------------------------------------
        // Pass 2: stream SHA-256 each candidate, group by hash
        // -------------------------------------------------------------
        var groups: [DuplicateGroup] = []
        var hashed = 0

        for bucket in candidateGroups {
            if Task.isCancelled { break }

            var byHash: [String: [Candidate]] = [:]
            for candidate in bucket {
                if Task.isCancelled { break }
                guard let digest = Self.sha256(of: candidate.url) else {
                    hashed += 1
                    continue
                }
                byHash[digest, default: []].append(candidate)

                hashed += 1
                if hashed % 25 == 0 {
                    let snap = hashed
                    let total = totalToHash
                    await MainActor.run { progressHandler(snap, total) }
                }
            }

            // Convert hash-buckets with 2+ entries into DuplicateGroup objects.
            for (hash, items) in byHash where items.count > 1 {
                let files = items.map { DuplicateFile(url: $0.url, modifiedDate: $0.modified) }
                let size = items.first?.size ?? 0
                groups.append(DuplicateGroup(hash: hash, size: size, files: files))
            }
        }

        // Final tick.
        let snap = hashed
        let total = totalToHash
        await MainActor.run { progressHandler(snap, total) }

        groups.sort { $0.wastedBytes > $1.wastedBytes }
        return groups
    }

    /// Pass-1 walker. Streams files under `folder` into `bySize`, calling the
    /// progress handler every 500 files visited.
    private func collectCandidates(
        in folder: URL,
        minimumSize: Int64,
        bySize: inout [Int64: [Candidate]],
        visited: inout Int,
        progressHandler: @MainActor @escaping (Int, Int) -> Void
    ) async {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        while let next = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }

            visited += 1
            if visited % 500 == 0 {
                let snap = visited
                await MainActor.run { progressHandler(snap, 0) }
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

            let candidate = Candidate(
                url: next,
                size: size,
                modified: values.contentModificationDate
            )
            bySize[size, default: []].append(candidate)
        }
    }

    /// Move all `urls` to Trash. Duplicates are scary to nuke, so we ALWAYS use
    /// recoverable trashing — never `removeItem`.
    func delete(_ urls: [URL]) async -> (bytesFreed: Int64, errors: [FileCleanupError]) {
        var freed: Int64 = 0
        var errors: [FileCleanupError] = []

        for url in urls {
            // Capture size BEFORE trashing so we can report bytesFreed.
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                freed += size
            } catch {
                errors.append(FileCleanupError(
                    path: url.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        return (freed, errors)
    }

    // MARK: - SHA-256 (streaming, 1 MB chunks)

    /// Stream SHA-256 of the file at `url`. Returns the lowercase hex digest, or
    /// `nil` if the file could not be opened.
    nonisolated static func sha256(of url: URL) -> String? {
        let bufferSize = 1024 * 1024  // 1 MB

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data: Data
            do {
                data = try handle.read(upToCount: bufferSize) ?? Data()
            } catch {
                return nil
            }
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
