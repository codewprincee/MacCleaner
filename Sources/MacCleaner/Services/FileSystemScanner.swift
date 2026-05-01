import Foundation

actor FileSystemScanner {
    struct ScanResult {
        let bytesFreed: Int64
        let errors: [FileCleanupError]
    }

    private let fileManager = FileManager.default

    // System-protected cache directories that should never be deleted by user-level cleanup.
    // Managed by macOS and will always fail with "permission denied".
    private static let protectedCachePrefixes: Set<String> = [
        "com.apple.",
        "CloudKit",
        "com.crashlytics",
    ]

    func directorySize(at path: String) async -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }
        return Self.computeSize(at: path)
    }

    /// Calculate size only for items we can actually delete (skipping protected system dirs).
    func cleanableDirectorySize(at path: String) async -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return 0 }
        var total: Int64 = 0
        for name in contents {
            if isProtected(name) { continue }
            let itemPath = (path as NSString).appendingPathComponent(name)
            if !fileManager.isReadableFile(atPath: itemPath) { continue }
            total += Self.computeSize(at: itemPath)
        }
        return total
    }

    /// Delete top-level items in `path`, summing the size of each item that was successfully
    /// removed. This is more accurate than diffing pre/post directory size because background
    /// processes can write to caches between snapshots.
    func clearDirectory(at path: String, skipProtected: Bool = false) async -> ScanResult {
        let url = URL(fileURLWithPath: path)
        var errors: [FileCleanupError] = []

        guard fileManager.fileExists(atPath: path) else {
            errors.append(FileCleanupError(path: path, reason: "Directory does not exist"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            errors.append(FileCleanupError(path: path, reason: "Cannot read directory contents"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        var bytesFreed: Int64 = 0

        for item in contents {
            let name = item.lastPathComponent

            if skipProtected && isProtected(name) { continue }
            if skipProtected && !fileManager.isWritableFile(atPath: item.path) { continue }

            // Size BEFORE delete; if delete succeeds, count it.
            let itemSize = Self.computeSize(at: item.path)

            do {
                try fileManager.removeItem(at: item)
                bytesFreed += itemSize
            } catch {
                errors.append(FileCleanupError(
                    path: name,
                    reason: error.localizedDescription
                ))
            }
        }

        return ScanResult(bytesFreed: bytesFreed, errors: errors)
    }

    /// Privileged delete: shells out via osascript with admin rights. Path is single-quoted
    /// to defuse shell metacharacters; we still measure byte changes via a pre/post diff
    /// (best we can do without a privileged size walker).
    func clearDirectoryWithPrivileges(at path: String, shell: ShellCommandRunner) async -> ScanResult {
        var errors: [FileCleanupError] = []

        guard fileManager.fileExists(atPath: path) else {
            errors.append(FileCleanupError(path: path, reason: "Directory does not exist"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        let sizeBefore = Self.computeSize(at: path)
        let quoted = ShellCommandRunner.shellQuote(path)
        // `find ... -mindepth 1 -delete` removes everything inside `path` without nuking
        // `path` itself. Safer than `rm -rf '<path>'/*` because it doesn't depend on glob
        // expansion and won't follow symlinks pointing outside the directory.
        let command = "/usr/bin/find \(quoted) -mindepth 1 -depth -delete 2>&1"

        do {
            let result = try await shell.runWithPrivileges(command)
            if !result.success {
                errors.append(FileCleanupError(
                    path: path,
                    reason: result.output.isEmpty ? "Failed to remove files" : result.output
                ))
            }
        } catch ShellCommandRunner.ShellError.authorizationDenied {
            errors.append(FileCleanupError(
                path: path,
                reason: "Administrator access denied or cancelled"
            ))
        } catch {
            errors.append(FileCleanupError(
                path: path,
                reason: error.localizedDescription
            ))
        }

        let sizeAfter = Self.computeSize(at: path)
        return ScanResult(bytesFreed: max(sizeBefore - sizeAfter, 0), errors: errors)
    }

    func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Sum the size of every regular file under `path` whose URL satisfies `matches`.
    /// Used by predicate-based categories (old downloads, large screen recordings).
    func filteredSize(
        at path: String,
        matches: @Sendable @escaping (URL, URLResourceValues) -> Bool
    ) async -> Int64 {
        Self.filteredSizeSync(at: path, matches: matches)
    }

    /// Delete every regular file under `path` whose URL satisfies `matches`. Empty
    /// directories left behind are NOT removed (intentional — we don't want to remove
    /// the user's `~/Downloads` folder structure).
    func clearFilteredFiles(
        at path: String,
        matches: @Sendable @escaping (URL, URLResourceValues) -> Bool
    ) async -> ScanResult {
        var errors: [FileCleanupError] = []
        guard fileManager.fileExists(atPath: path) else {
            errors.append(FileCleanupError(path: path, reason: "Directory does not exist"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            errors.append(FileCleanupError(path: path, reason: "Cannot enumerate directory"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        var bytesFreed: Int64 = 0
        while let next = enumerator.nextObject() as? URL {
            guard let values = try? next.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]
            ) else { continue }

            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            if !matches(next, values) { continue }

            let size = Int64(values.fileSize ?? 0)
            do {
                try fileManager.removeItem(at: next)
                bytesFreed += size
            } catch {
                errors.append(FileCleanupError(
                    path: next.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }
        return ScanResult(bytesFreed: bytesFreed, errors: errors)
    }

    /// Aggregate the size of multiple paths that may or may not exist.
    func combinedSize(of paths: [String]) async -> Int64 {
        var total: Int64 = 0
        for p in paths {
            total += await directorySize(at: p)
        }
        return total
    }

    /// Clear several directories in sequence, accumulating bytes freed and errors.
    /// Skips paths that do not exist (silently — non-existent paths are not failures).
    func clearDirectories(at paths: [String]) async -> ScanResult {
        var totalBytes: Int64 = 0
        var errors: [FileCleanupError] = []
        for p in paths {
            guard fileManager.fileExists(atPath: p) else { continue }
            let result = await clearDirectory(at: p)
            totalBytes += result.bytesFreed
            errors.append(contentsOf: result.errors)
        }
        return ScanResult(bytesFreed: totalBytes, errors: errors)
    }

    /// Clear specific subdirectories (by name) of `parent`. Used by the cargo registry
    /// cleaner which must preserve the `index/` subdir while wiping `cache/` and `src/`.
    /// If a subdirectory doesn't exist it is silently skipped.
    func clearSubdirectories(of parent: String, named subdirs: [String]) async -> ScanResult {
        var totalBytes: Int64 = 0
        var errors: [FileCleanupError] = []
        guard fileManager.fileExists(atPath: parent) else {
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        for subdir in subdirs {
            // Each direct child of `parent/subdir` is removed; the `subdir` itself stays
            // so cargo doesn't recreate it with broken permissions.
            let path = (parent as NSString).appendingPathComponent(subdir)
            guard fileManager.fileExists(atPath: path) else { continue }
            let result = await clearDirectory(at: path)
            totalBytes += result.bytesFreed
            errors.append(contentsOf: result.errors)
        }
        return ScanResult(bytesFreed: totalBytes, errors: errors)
    }

    /// Find immediate child directories of `parent` whose names match `predicate`.
    /// Used to discover Mail.app's versioned `V*/MailData/Attachments` paths.
    func childDirectories(
        of parent: String,
        matching predicate: @Sendable (String) -> Bool
    ) async -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: parent) else { return [] }
        var out: [String] = []
        for name in names where predicate(name) {
            let p = (parent as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                out.append(p)
            }
        }
        return out
    }

    private func isProtected(_ name: String) -> Bool {
        for prefix in Self.protectedCachePrefixes {
            if name.hasPrefix(prefix) { return true }
        }
        return false
    }

    // MARK: - Synchronous size walker (Swift 6 friendly)

    /// Recursively sum file sizes under `path`. Synchronous & nonisolated so it can be
    /// invoked from the actor without async-iterator issues. Skips symlinks to avoid loops.
    nonisolated static func computeSize(at path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return fileSize(at: path)
        }

        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        while let next = enumerator.nextObject() as? URL {
            guard let values = try? next.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
            ) else { continue }

            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    nonisolated private static func fileSize(at path: String) -> Int64 {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return 0 }
        return (attrs[.size] as? Int64) ?? 0
    }

    /// Predicate-based size walker. Mirrors `computeSize` but only counts files that
    /// pass `matches`. Synchronous so it can be invoked from the actor without the
    /// async-iterator dance.
    nonisolated static func filteredSizeSync(
        at path: String,
        matches: (URL, URLResourceValues) -> Bool
    ) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return 0 }

        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        while let next = enumerator.nextObject() as? URL {
            guard let values = try? next.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]
            ) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            if !matches(next, values) { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
