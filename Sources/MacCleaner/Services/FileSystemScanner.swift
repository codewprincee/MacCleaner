import Foundation

actor FileSystemScanner {
    struct ScanResult {
        let bytesFreed: Int64
        let errors: [FileCleanupError]
    }

    private let fileManager = FileManager.default

    // System-protected cache directories that should never be deleted by user-level cleanup.
    // These are managed by macOS and will always fail with "permission denied".
    private static let protectedCachePrefixes: Set<String> = [
        "com.apple.",
        "CloudKit",
        "com.crashlytics",
    ]

    func directorySize(at path: String) async -> Int64 {
        let url = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: path) else {
            return 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey]
            ) else {
                continue
            }

            if resourceValues.isDirectory == false {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }

        return totalSize
    }

    /// Calculate size only for items we can actually delete (skipping protected system dirs).
    func cleanableDirectorySize(at path: String) async -> Int64 {
        let url = URL(fileURLWithPath: path)

        guard fileManager.fileExists(atPath: path) else { return 0 }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        ) else { return 0 }

        var totalSize: Int64 = 0
        for item in contents {
            let name = item.lastPathComponent
            if isProtected(name) { continue }
            if !fileManager.isWritableFile(atPath: item.path) { continue }
            totalSize += await directorySize(at: item.path)
        }
        return totalSize
    }

    func clearDirectory(at path: String, skipProtected: Bool = false) async -> ScanResult {
        let url = URL(fileURLWithPath: path)
        var errors: [FileCleanupError] = []

        guard fileManager.fileExists(atPath: path) else {
            errors.append(FileCleanupError(path: path, reason: "Directory does not exist"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        let sizeBefore = await directorySize(at: path)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            errors.append(FileCleanupError(path: path, reason: "Cannot read directory contents"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        for item in contents {
            let name = item.lastPathComponent

            // Skip system-protected directories when cleaning user caches
            if skipProtected && isProtected(name) {
                continue
            }

            // Skip items we clearly can't write to
            if skipProtected && !fileManager.isWritableFile(atPath: item.path) {
                continue
            }

            do {
                try fileManager.removeItem(at: item)
            } catch {
                errors.append(FileCleanupError(
                    path: name,
                    reason: error.localizedDescription
                ))
            }
        }

        let sizeAfter = await directorySize(at: path)
        return ScanResult(bytesFreed: max(sizeBefore - sizeAfter, 0), errors: errors)
    }

    func clearDirectoryWithPrivileges(at path: String, shell: ShellCommandRunner) async -> ScanResult {
        var errors: [FileCleanupError] = []

        guard fileManager.fileExists(atPath: path) else {
            errors.append(FileCleanupError(path: path, reason: "Directory does not exist"))
            return ScanResult(bytesFreed: 0, errors: errors)
        }

        let sizeBefore = await directorySize(at: path)

        let command = "rm -rf \(path)/* 2>&1"
        do {
            let result = try await shell.runWithPrivileges(command)
            if !result.success {
                errors.append(FileCleanupError(
                    path: path,
                    reason: result.output.isEmpty ? "Failed to remove files" : result.output
                ))
            }
        } catch {
            errors.append(FileCleanupError(
                path: path,
                reason: "Administrator access denied or cancelled"
            ))
        }

        let sizeAfter = await directorySize(at: path)
        return ScanResult(bytesFreed: max(sizeBefore - sizeAfter, 0), errors: errors)
    }

    func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func isProtected(_ name: String) -> Bool {
        for prefix in Self.protectedCachePrefixes {
            if name.hasPrefix(prefix) { return true }
        }
        return false
    }
}
