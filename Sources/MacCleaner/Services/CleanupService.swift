import Foundation

actor CleanupService {
    private let scanner = FileSystemScanner()
    private let shell = ShellCommandRunner()
    private let docker = DockerService()

    // MARK: - Availability Checks

    func checkAvailability(for type: CleanupType) async -> (available: Bool, reason: String?) {
        switch type {
        case .userCaches:
            let exists = await scanner.directoryExists(at: Constants.userCachesPath)
            return (exists, exists ? nil : "Directory not found")

        case .systemLogs:
            let exists = await scanner.directoryExists(at: Constants.systemLogsPath)
            return (exists, exists ? nil : "Directory not found")

        case .xcodeDerivedData:
            let exists = await scanner.directoryExists(at: Constants.xcodeDerivedDataPath)
            return (exists, exists ? nil : "Xcode DerivedData not found")

        case .xcodeDeviceSupport:
            let exists = await scanner.directoryExists(at: Constants.xcodeDeviceSupportPath)
            return (exists, exists ? nil : "iOS DeviceSupport not found")

        case .xcodeSimulators:
            let available = await shell.isToolAvailable(Constants.xcodeSelectCheckCommand)
            return (available, available ? nil : "Xcode not installed")

        case .xcodeArchives:
            let exists = await scanner.directoryExists(at: Constants.xcodeArchivesPath)
            return (exists, exists ? nil : "No Xcode archives found")

        case .trash:
            return (true, nil)

        case .safariCache:
            let exists = await scanner.directoryExists(at: Constants.safariCachePath)
            return (exists, exists ? nil : "Safari cache not found")

        case .chromeCache:
            let exists = await scanner.directoryExists(at: Constants.chromeCachePath)
            return (exists, exists ? nil : "Chrome not installed")

        case .homebrewCache:
            let available = await shell.isToolAvailable(Constants.brewCheckCommand)
            return (available, available ? nil : "Homebrew not installed")

        case .npmCache:
            let available = await shell.isToolAvailable(Constants.npmCheckCommand)
            return (available, available ? nil : "npm not installed")

        case .pipCache:
            let available = await shell.isToolAvailable(Constants.pipCheckCommand)
            return (available, available ? nil : "pip3 not installed")

        case .yarnCache:
            let available = await shell.isToolAvailable(Constants.yarnCheckCommand)
            return (available, available ? nil : "Yarn not installed")

        case .cocoapodsCache:
            let available = await shell.isToolAvailable(Constants.cocoapodsCheckCommand)
            return (available, available ? nil : "CocoaPods not installed")

        case .tempFiles:
            return (true, nil)

        case .systemCaches:
            return (true, nil)

        case .dnsCache:
            return (true, nil)

        case .dockerData:
            let available = await docker.isDockerAvailable()
            return (available, available ? nil : "Docker not running")
        }
    }

    // MARK: - Size Estimation

    func estimateSize(for type: CleanupType) async -> Int64 {
        switch type {
        case .userCaches:
            return await scanner.cleanableDirectorySize(at: Constants.userCachesPath)

        case .systemLogs:
            return await scanner.cleanableDirectorySize(at: Constants.systemLogsPath)

        case .xcodeDerivedData:
            return await scanner.directorySize(at: Constants.xcodeDerivedDataPath)

        case .xcodeDeviceSupport:
            return await scanner.directorySize(at: Constants.xcodeDeviceSupportPath)

        case .xcodeSimulators:
            // Simulator size is hard to estimate without parsing xcrun output
            let simPath = NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices"
            return await scanner.directorySize(at: simPath)

        case .xcodeArchives:
            return await scanner.directorySize(at: Constants.xcodeArchivesPath)

        case .trash:
            return await scanner.directorySize(at: Constants.trashPath)

        case .safariCache:
            return await scanner.directorySize(at: Constants.safariCachePath)

        case .chromeCache:
            return await scanner.directorySize(at: Constants.chromeCachePath)

        case .homebrewCache:
            return await estimateBrewCacheSize()

        case .npmCache:
            return await estimateNpmCacheSize()

        case .pipCache:
            return await estimatePipCacheSize()

        case .yarnCache:
            return await estimateYarnCacheSize()

        case .cocoapodsCache:
            return await scanner.directorySize(at: Constants.cocoapodsCachePath)

        case .tempFiles:
            return await scanner.directorySize(at: Constants.tempPath)

        case .systemCaches:
            return await scanner.directorySize(at: Constants.systemCachesPath)

        case .dnsCache:
            return 0 // DNS cache has negligible disk usage

        case .dockerData:
            return await docker.estimateDiskUsage()
        }
    }

    // MARK: - Cleanup

    func clean(_ type: CleanupType) async -> CleanupResult {
        switch type {
        // File system categories (user-level, skip system-protected dirs)
        case .userCaches:
            return await cleanDirectory(Constants.userCachesPath, type: type, skipProtected: true)

        case .systemLogs:
            return await cleanDirectory(Constants.systemLogsPath, type: type, skipProtected: true)

        case .xcodeDerivedData:
            return await cleanDirectory(Constants.xcodeDerivedDataPath, type: type)

        case .xcodeDeviceSupport:
            return await cleanDirectory(Constants.xcodeDeviceSupportPath, type: type)

        case .xcodeArchives:
            return await cleanDirectory(Constants.xcodeArchivesPath, type: type)

        case .trash:
            return await cleanDirectory(Constants.trashPath, type: type)

        case .safariCache:
            return await cleanDirectory(Constants.safariCachePath, type: type)

        case .chromeCache:
            return await cleanDirectory(Constants.chromeCachePath, type: type)

        // Temp files - try user first, then escalate
        case .tempFiles:
            return await cleanDirectory(Constants.tempPath, type: type)

        // Shell command categories
        case .xcodeSimulators:
            return await cleanWithShellCommand(
                command: Constants.xcodeSimulatorsCleanCommand,
                type: type
            )

        case .homebrewCache:
            return await cleanWithShellCommand(
                command: Constants.brewCleanupCommand,
                type: type,
                sizeBefore: await estimateBrewCacheSize(),
                sizeAfterEstimator: { await self.estimateBrewCacheSize() }
            )

        case .npmCache:
            return await cleanWithShellCommand(
                command: Constants.npmCacheCleanCommand,
                type: type,
                sizeBefore: await estimateNpmCacheSize(),
                sizeAfterEstimator: { await self.estimateNpmCacheSize() }
            )

        case .pipCache:
            return await cleanWithShellCommand(
                command: Constants.pipCachePurgeCommand,
                type: type,
                sizeBefore: await estimatePipCacheSize(),
                sizeAfterEstimator: { await self.estimatePipCacheSize() }
            )

        case .yarnCache:
            return await cleanWithShellCommand(
                command: Constants.yarnCacheCleanCommand,
                type: type,
                sizeBefore: await estimateYarnCacheSize(),
                sizeAfterEstimator: { await self.estimateYarnCacheSize() }
            )

        case .cocoapodsCache:
            let sizeBefore = await scanner.directorySize(at: Constants.cocoapodsCachePath)
            return await cleanWithShellCommand(
                command: Constants.cocoapodsCacheCleanCommand,
                type: type,
                sizeBefore: sizeBefore,
                sizeAfterEstimator: { await self.scanner.directorySize(at: Constants.cocoapodsCachePath) }
            )

        // Elevated privilege categories
        case .systemCaches:
            return await cleanDirectoryWithPrivileges(Constants.systemCachesPath, type: type)

        case .dnsCache:
            return await cleanDNSCache()

        case .dockerData:
            return await cleanDocker()
        }
    }

    // MARK: - Clean Helpers

    private func cleanDirectory(_ path: String, type: CleanupType, skipProtected: Bool = false) async -> CleanupResult {
        let scan = await scanner.clearDirectory(at: path, skipProtected: skipProtected)
        let success = scan.errors.isEmpty
        let partial = !success && scan.bytesFreed > 0
        return CleanupResult(
            type: type,
            bytesFreed: scan.bytesFreed,
            success: success || partial,
            message: success ? "Cleaned successfully" : "Partially cleaned (\(scan.errors.count) errors)",
            errors: scan.errors,
            partialSuccess: partial
        )
    }

    private func cleanDirectoryWithPrivileges(_ path: String, type: CleanupType) async -> CleanupResult {
        let scan = await scanner.clearDirectoryWithPrivileges(at: path, shell: shell)
        let success = scan.errors.isEmpty
        let partial = !success && scan.bytesFreed > 0
        return CleanupResult(
            type: type,
            bytesFreed: scan.bytesFreed,
            success: success || partial,
            message: success ? "Cleaned successfully" : (scan.bytesFreed > 0 ? "Partially cleaned" : "Failed"),
            errors: scan.errors,
            partialSuccess: partial
        )
    }

    private func cleanWithShellCommand(
        command: String,
        type: CleanupType,
        sizeBefore: Int64 = 0,
        sizeAfterEstimator: (() async -> Int64)? = nil
    ) async -> CleanupResult {
        do {
            let result = try await shell.run(command)
            if !result.success {
                return CleanupResult(
                    type: type, bytesFreed: 0, success: false,
                    message: result.output,
                    errors: [FileCleanupError(path: type.rawValue, reason: result.output)]
                )
            }

            var bytesFreed: Int64 = 0
            if let estimator = sizeAfterEstimator {
                let sizeAfter = await estimator()
                bytesFreed = max(sizeBefore - sizeAfter, 0)
            }

            return CleanupResult(
                type: type, bytesFreed: bytesFreed, success: true,
                message: "Cleaned successfully"
            )
        } catch {
            return CleanupResult(
                type: type, bytesFreed: 0, success: false,
                message: error.localizedDescription,
                errors: [FileCleanupError(path: type.rawValue, reason: error.localizedDescription)]
            )
        }
    }

    private func cleanDNSCache() async -> CleanupResult {
        do {
            let result = try await shell.runWithPrivileges(Constants.dnsFlushCommand)
            if result.success {
                return CleanupResult(
                    type: .dnsCache, bytesFreed: 0, success: true,
                    message: "DNS cache flushed"
                )
            } else {
                return CleanupResult(
                    type: .dnsCache, bytesFreed: 0, success: false,
                    message: result.output,
                    errors: [FileCleanupError(path: "DNS", reason: result.output)]
                )
            }
        } catch {
            return CleanupResult(
                type: .dnsCache, bytesFreed: 0, success: false,
                message: "Administrator access denied",
                errors: [FileCleanupError(path: "DNS", reason: error.localizedDescription)]
            )
        }
    }

    private func cleanDocker() async -> CleanupResult {
        do {
            let bytesFreed = try await docker.prune()
            return CleanupResult(
                type: .dockerData, bytesFreed: bytesFreed, success: true,
                message: "Cleaned successfully"
            )
        } catch {
            return CleanupResult(
                type: .dockerData, bytesFreed: 0, success: false,
                message: error.localizedDescription,
                errors: [FileCleanupError(path: "Docker", reason: error.localizedDescription)]
            )
        }
    }

    // MARK: - Size Estimation Helpers

    private func estimateBrewCacheSize() async -> Int64 {
        guard let result = try? await shell.run(Constants.brewCacheSizeCommand),
              result.success else {
            return 0
        }
        let cachePath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachePath.isEmpty else { return 0 }
        return await scanner.directorySize(at: cachePath)
    }

    private func estimateNpmCacheSize() async -> Int64 {
        guard let pathResult = try? await shell.run("npm config get cache 2>/dev/null"),
              pathResult.success else {
            return 0
        }
        let cachePath = pathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachePath.isEmpty else { return 0 }
        return await scanner.directorySize(at: cachePath)
    }

    private func estimatePipCacheSize() async -> Int64 {
        if let dirResult = try? await shell.run("pip3 cache dir 2>/dev/null"),
           dirResult.success {
            let dir = dirResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dir.isEmpty {
                return await scanner.directorySize(at: dir)
            }
        }
        return 0
    }

    private func estimateYarnCacheSize() async -> Int64 {
        guard let result = try? await shell.run(Constants.yarnCacheDirCommand),
              result.success else {
            return 0
        }
        let cachePath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachePath.isEmpty else { return 0 }
        return await scanner.directorySize(at: cachePath)
    }
}
