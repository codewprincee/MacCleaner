import Foundation

actor CleanupService {
    private let scanner = FileSystemScanner()
    private let shell = ShellCommandRunner()
    private let docker: DockerService

    init() {
        self.docker = DockerService(shell: ShellCommandRunner())
    }

    // MARK: - Preflight

    /// Returns the set of running apps that conflict with cleaning the given types.
    /// Callers should warn (or refuse) before proceeding.
    nonisolated func preflightConflicts(for types: [CleanupType]) -> [CleanupType: [ConflictingApp]] {
        var result: [CleanupType: [ConflictingApp]] = [:]
        for type in types {
            let conflicts = RunningProcessDetector.conflictingApps(for: type)
            if !conflicts.isEmpty { result[type] = conflicts }
        }
        return result
    }

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

        case .braveCache:
            let exists = await scanner.directoryExists(at: Constants.braveCachePath)
            return (exists, exists ? nil : "Brave not installed")

        case .arcCache:
            let primary = await scanner.directoryExists(at: Constants.arcCachePathPrimary)
            let secondary = await scanner.directoryExists(at: Constants.arcCachePathSecondary)
            return (primary || secondary, (primary || secondary) ? nil : "Arc not installed")

        case .edgeCache:
            let exists = await scanner.directoryExists(at: Constants.edgeCachePath)
            return (exists, exists ? nil : "Edge not installed")

        case .firefoxCache:
            let exists = await scanner.directoryExists(at: Constants.firefoxCachePath)
            return (exists, exists ? nil : "Firefox not installed")

        case .vivaldiCache:
            let exists = await scanner.directoryExists(at: Constants.vivaldiCachePath)
            return (exists, exists ? nil : "Vivaldi not installed")

        case .operaCache:
            let exists = await scanner.directoryExists(at: Constants.operaCachePath)
            return (exists, exists ? nil : "Opera not installed")

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

        case .cargoCache:
            let available = await shell.isToolAvailable(Constants.cargoCheckCommand)
            return (available, available ? nil : "Rust / cargo not installed")

        case .goModuleCache:
            let available = await shell.isToolAvailable(Constants.goCheckCommand)
            return (available, available ? nil : "Go not installed")

        case .condaCache:
            let available = await shell.isToolAvailable(Constants.condaCheckCommand)
            return (available, available ? nil : "Conda not installed")

        case .bundlerCache:
            let bundle = await shell.isToolAvailable(Constants.bundleCheckCommand)
            let gem = await shell.isToolAvailable(Constants.gemCheckCommand)
            let available = bundle || gem
            return (available, available ? nil : "Ruby bundler/gem not installed")

        case .gradleCache:
            let exists = await scanner.directoryExists(at: Constants.gradleCachePath)
            return (exists, exists ? nil : "Gradle cache not found")

        case .mavenCache:
            let exists = await scanner.directoryExists(at: Constants.mavenRepositoryPath)
            return (exists, exists ? nil : "Maven repository not found")

        case .composerCache:
            var anyExists = false
            for path in Constants.composerCachePaths {
                if await scanner.directoryExists(at: path) { anyExists = true; break }
            }
            return (anyExists, anyExists ? nil : "Composer cache not found")

        case .tempFiles:
            return (true, nil)

        case .systemCaches:
            return (true, nil)

        case .dnsCache:
            return (true, nil)

        case .diagnosticReports:
            let user = await scanner.directoryExists(at: Constants.userDiagnosticReportsPath)
            let system = await scanner.directoryExists(at: Constants.systemDiagnosticReportsPath)
            return (user || system, (user || system) ? nil : "No diagnostic reports found")

        case .crashReporter:
            let user = await scanner.directoryExists(at: Constants.userCrashReporterPath)
            let system = await scanner.directoryExists(at: Constants.systemCrashReporterPath)
            return (user || system, (user || system) ? nil : "No crash reports found")

        case .timeMachineLocalSnapshots:
            // tmutil ships with macOS — always available.
            return (true, nil)

        case .downloadsOldFiles:
            let exists = await scanner.directoryExists(at: Constants.downloadsPath)
            return (exists, exists ? nil : "Downloads folder not found")

        case .mailDownloads:
            let container = await scanner.directoryExists(at: Constants.mailContainerDownloadsPath)
            let legacy = await scanner.directoryExists(at: Constants.mailDataPath)
            return (container || legacy, (container || legacy) ? nil : "No Mail data found")

        case .iosBackups:
            let exists = await scanner.directoryExists(at: Constants.iosBackupsPath)
            return (exists, exists ? nil : "No iOS backups found")

        case .quicktimeRecordings:
            // Always available — we just walk Desktop/Documents/Movies for matches.
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
            return await scanner.directorySize(at: Constants.userCachesPath)

        case .systemLogs:
            return await scanner.directorySize(at: Constants.systemLogsPath)

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

        case .braveCache:
            return await scanner.directorySize(at: Constants.braveCachePath)

        case .arcCache:
            return await scanner.combinedSize(of: [
                Constants.arcCachePathPrimary,
                Constants.arcCachePathSecondary,
            ])

        case .edgeCache:
            return await scanner.directorySize(at: Constants.edgeCachePath)

        case .firefoxCache:
            return await scanner.directorySize(at: Constants.firefoxCachePath)

        case .vivaldiCache:
            return await scanner.directorySize(at: Constants.vivaldiCachePath)

        case .operaCache:
            return await scanner.directorySize(at: Constants.operaCachePath)

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

        case .cargoCache:
            return await scanner.combinedSize(of: [
                Constants.cargoRegistryPath,
                Constants.cargoGitPath,
            ])

        case .goModuleCache:
            let path = await resolveGoModCachePath()
            return await scanner.directorySize(at: path)

        case .condaCache:
            return await scanner.combinedSize(of: Constants.condaCachePaths)

        case .bundlerCache:
            return await scanner.combinedSize(of: Constants.bundlerCachePaths)

        case .gradleCache:
            return await scanner.directorySize(at: Constants.gradleCachePath)

        case .mavenCache:
            return await scanner.directorySize(at: Constants.mavenRepositoryPath)

        case .composerCache:
            return await scanner.combinedSize(of: Constants.composerCachePaths)

        case .tempFiles:
            return await scanner.directorySize(at: Constants.tempPath)

        case .systemCaches:
            return await scanner.directorySize(at: Constants.systemCachesPath)

        case .dnsCache:
            return 0 // DNS cache has negligible disk usage

        case .diagnosticReports:
            return await scanner.combinedSize(of: [
                Constants.userDiagnosticReportsPath,
                Constants.systemDiagnosticReportsPath,
            ])

        case .crashReporter:
            return await scanner.combinedSize(of: [
                Constants.userCrashReporterPath,
                Constants.systemCrashReporterPath,
            ])

        case .timeMachineLocalSnapshots:
            // Local snapshots live in "purgeable" space and aren't visible to du. APFS
            // doesn't expose a cheap byte total, so we display 0 and let tmutil report
            // its own progress when cleaning.
            return 0

        case .downloadsOldFiles:
            let cutoff = Date().addingTimeInterval(-Constants.oldDownloadsAgeSeconds)
            return await scanner.filteredSize(at: Constants.downloadsPath) { _, values in
                Self.fileIsOlderThan(cutoff, values: values)
            }

        case .mailDownloads:
            let attachmentDirs = await resolveMailAttachmentPaths()
            var total: Int64 = 0
            total += await scanner.directorySize(at: Constants.mailContainerDownloadsPath)
            for dir in attachmentDirs {
                total += await scanner.directorySize(at: dir)
            }
            return total

        case .iosBackups:
            return await scanner.directorySize(at: Constants.iosBackupsPath)

        case .quicktimeRecordings:
            return await estimateScreenRecordingsSize()

        case .dockerData:
            return await docker.estimateDiskUsage()
        }
    }

    // MARK: - Cleanup

    func clean(_ type: CleanupType) async -> CleanupResult {
        switch type {
        // File system categories - use admin privileges to clean everything
        case .userCaches:
            return await cleanDirectoryWithPrivileges(Constants.userCachesPath, type: type)

        case .systemLogs:
            return await cleanDirectoryWithPrivileges(Constants.systemLogsPath, type: type)

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

        case .braveCache:
            return await cleanDirectory(Constants.braveCachePath, type: type)

        case .arcCache:
            return await cleanMultipleDirectories(
                paths: [Constants.arcCachePathPrimary, Constants.arcCachePathSecondary],
                type: type
            )

        case .edgeCache:
            return await cleanDirectory(Constants.edgeCachePath, type: type)

        case .firefoxCache:
            return await cleanDirectory(Constants.firefoxCachePath, type: type)

        case .vivaldiCache:
            return await cleanDirectory(Constants.vivaldiCachePath, type: type)

        case .operaCache:
            return await cleanDirectory(Constants.operaCachePath, type: type)

        // Temp files - use admin to clean other users' files too
        case .tempFiles:
            return await cleanDirectoryWithPrivileges(Constants.tempPath, type: type)

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

        case .cargoCache:
            return await cleanCargoCache()

        case .goModuleCache:
            let path = await resolveGoModCachePath()
            let sizeBefore = await scanner.directorySize(at: path)
            return await cleanWithShellCommand(
                command: Constants.goModCleanCommand,
                type: type,
                sizeBefore: sizeBefore,
                sizeAfterEstimator: { [scanner] in
                    await scanner.directorySize(at: path)
                }
            )

        case .condaCache:
            let sizeBefore = await scanner.combinedSize(of: Constants.condaCachePaths)
            return await cleanWithShellCommand(
                command: Constants.condaCleanCommand,
                type: type,
                sizeBefore: sizeBefore,
                sizeAfterEstimator: { [scanner] in
                    await scanner.combinedSize(of: Constants.condaCachePaths)
                }
            )

        case .bundlerCache:
            return await cleanMultipleDirectories(paths: Constants.bundlerCachePaths, type: type)

        case .gradleCache:
            return await cleanDirectory(Constants.gradleCachePath, type: type)

        case .mavenCache:
            return await cleanDirectory(Constants.mavenRepositoryPath, type: type)

        case .composerCache:
            return await cleanMultipleDirectories(paths: Constants.composerCachePaths, type: type)

        // Elevated privilege categories
        case .systemCaches:
            return await cleanDirectoryWithPrivileges(Constants.systemCachesPath, type: type)

        case .dnsCache:
            return await cleanDNSCache()

        case .diagnosticReports:
            return await cleanDiagnosticReports()

        case .crashReporter:
            return await cleanCrashReporter()

        case .timeMachineLocalSnapshots:
            return await cleanTimeMachineLocalSnapshots()

        case .downloadsOldFiles:
            return await cleanOldDownloads()

        case .mailDownloads:
            return await cleanMailDownloads()

        case .iosBackups:
            return await cleanDirectory(Constants.iosBackupsPath, type: type)

        case .quicktimeRecordings:
            return await cleanScreenRecordings()

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

    /// Clean several directories non-privileged. Reports success only if every
    /// existing path was cleaned without errors.
    private func cleanMultipleDirectories(paths: [String], type: CleanupType) async -> CleanupResult {
        let scan = await scanner.clearDirectories(at: paths)
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

    // MARK: - New Cleanup Implementations

    /// Cargo cache: prefer the `cargo-cache` plugin's `--autoclean` (which keeps the
    /// useful bits and removes the rest), otherwise fall back to filesystem cleanup
    /// of `registry/cache` and `registry/src` only — NEVER touch `registry/index`,
    /// which is the registry crate index and would force a full re-fetch on next build.
    private func cleanCargoCache() async -> CleanupResult {
        let sizeBefore = await scanner.combinedSize(of: [
            Constants.cargoRegistryPath,
            Constants.cargoGitPath,
        ])

        let pluginAvailable = await shell.isToolAvailable(Constants.cargoAutocleanCheckCommand)
        if pluginAvailable {
            return await cleanWithShellCommand(
                command: Constants.cargoAutocleanCommand,
                type: .cargoCache,
                sizeBefore: sizeBefore,
                sizeAfterEstimator: { [scanner] in
                    await scanner.combinedSize(of: [
                        Constants.cargoRegistryPath,
                        Constants.cargoGitPath,
                    ])
                }
            )
        }

        // Fallback: scrub registry/cache + registry/src, plus the entire git checkouts dir.
        // The git checkouts can be re-fetched safely.
        let registryClean = await scanner.clearSubdirectories(
            of: Constants.cargoRegistryPath,
            named: Constants.cargoRegistryCleanableSubdirs
        )
        let gitClean = await scanner.clearDirectory(at: Constants.cargoGitPath)

        let bytesFreed = registryClean.bytesFreed + gitClean.bytesFreed
        let allErrors = registryClean.errors + gitClean.errors
        let success = allErrors.isEmpty
        let partial = !success && bytesFreed > 0
        return CleanupResult(
            type: .cargoCache,
            bytesFreed: bytesFreed,
            success: success || partial,
            message: success ? "Cleaned successfully (registry index preserved)"
                              : "Partially cleaned (\(allErrors.count) errors)",
            errors: allErrors,
            partialSuccess: partial
        )
    }

    private func cleanDiagnosticReports() async -> CleanupResult {
        return await cleanUserAndSystemPaths(
            userPath: Constants.userDiagnosticReportsPath,
            systemPath: Constants.systemDiagnosticReportsPath,
            type: .diagnosticReports
        )
    }

    private func cleanCrashReporter() async -> CleanupResult {
        return await cleanUserAndSystemPaths(
            userPath: Constants.userCrashReporterPath,
            systemPath: Constants.systemCrashReporterPath,
            type: .crashReporter
        )
    }

    /// Generic helper: clean a user-owned path normally, then clean the parallel
    /// system-owned path with admin rights. Aggregates bytes and errors.
    private func cleanUserAndSystemPaths(
        userPath: String,
        systemPath: String,
        type: CleanupType
    ) async -> CleanupResult {
        var totalBytes: Int64 = 0
        var allErrors: [FileCleanupError] = []

        if await scanner.directoryExists(at: userPath) {
            let userScan = await scanner.clearDirectory(at: userPath)
            totalBytes += userScan.bytesFreed
            allErrors.append(contentsOf: userScan.errors)
        }

        if await scanner.directoryExists(at: systemPath) {
            let systemScan = await scanner.clearDirectoryWithPrivileges(at: systemPath, shell: shell)
            totalBytes += systemScan.bytesFreed
            allErrors.append(contentsOf: systemScan.errors)
        }

        let success = allErrors.isEmpty
        let partial = !success && totalBytes > 0
        return CleanupResult(
            type: type,
            bytesFreed: totalBytes,
            success: success || partial,
            message: success ? "Cleaned successfully" : "Partially cleaned (\(allErrors.count) errors)",
            errors: allErrors,
            partialSuccess: partial
        )
    }

    private func cleanTimeMachineLocalSnapshots() async -> CleanupResult {
        do {
            let result = try await shell.runWithPrivileges(Constants.timeMachineThinSnapshotsCommand)
            if result.success {
                return CleanupResult(
                    type: .timeMachineLocalSnapshots,
                    bytesFreed: 0, // tmutil doesn't report bytes; APFS purgeable space isn't directly measurable
                    success: true,
                    message: result.output.isEmpty ? "Local snapshots removed" : result.output
                )
            } else {
                return CleanupResult(
                    type: .timeMachineLocalSnapshots, bytesFreed: 0, success: false,
                    message: result.output,
                    errors: [FileCleanupError(path: "tmutil", reason: result.output)]
                )
            }
        } catch {
            return CleanupResult(
                type: .timeMachineLocalSnapshots, bytesFreed: 0, success: false,
                message: error.localizedDescription,
                errors: [FileCleanupError(path: "tmutil", reason: error.localizedDescription)]
            )
        }
    }

    private func cleanOldDownloads() async -> CleanupResult {
        let cutoff = Date().addingTimeInterval(-Constants.oldDownloadsAgeSeconds)
        let scan = await scanner.clearFilteredFiles(at: Constants.downloadsPath) { _, values in
            Self.fileIsOlderThan(cutoff, values: values)
        }
        let success = scan.errors.isEmpty
        let partial = !success && scan.bytesFreed > 0
        return CleanupResult(
            type: .downloadsOldFiles,
            bytesFreed: scan.bytesFreed,
            success: success || partial,
            message: success ? "Cleaned successfully" : "Partially cleaned (\(scan.errors.count) errors)",
            errors: scan.errors,
            partialSuccess: partial
        )
    }

    private func cleanMailDownloads() async -> CleanupResult {
        var paths: [String] = []
        if await scanner.directoryExists(at: Constants.mailContainerDownloadsPath) {
            paths.append(Constants.mailContainerDownloadsPath)
        }
        paths.append(contentsOf: await resolveMailAttachmentPaths())

        if paths.isEmpty {
            return CleanupResult(
                type: .mailDownloads, bytesFreed: 0, success: false,
                message: "No Mail data found",
                errors: [FileCleanupError(path: "Mail", reason: "No accessible Mail directories")]
            )
        }

        let scan = await scanner.clearDirectories(at: paths)
        let success = scan.errors.isEmpty
        let partial = !success && scan.bytesFreed > 0

        // Surface a hint about Full Disk Access when nothing could be removed —
        // the most common cause is missing TCC permission for the sandboxed Mail container.
        let message: String
        if success {
            message = "Cleaned successfully"
        } else if partial {
            message = "Partially cleaned — grant Full Disk Access for complete cleanup"
        } else {
            message = "Failed — Mail Downloads requires Full Disk Access in System Settings > Privacy & Security"
        }

        return CleanupResult(
            type: .mailDownloads,
            bytesFreed: scan.bytesFreed,
            success: success || partial,
            message: message,
            errors: scan.errors,
            partialSuccess: partial
        )
    }

    private func cleanScreenRecordings() async -> CleanupResult {
        let threshold = Constants.largeScreenRecordingThreshold
        let matcher: @Sendable (URL, URLResourceValues) -> Bool = { url, values in
            Self.isScreenRecording(url: url, values: values, minSize: threshold)
        }

        var totalBytes: Int64 = 0
        var allErrors: [FileCleanupError] = []
        for path in [Constants.desktopPath, Constants.documentsPath, Constants.moviesPath] {
            guard await scanner.directoryExists(at: path) else { continue }
            let scan = await scanner.clearFilteredFiles(at: path, matches: matcher)
            totalBytes += scan.bytesFreed
            allErrors.append(contentsOf: scan.errors)
        }

        let success = allErrors.isEmpty
        let partial = !success && totalBytes > 0
        return CleanupResult(
            type: .quicktimeRecordings,
            bytesFreed: totalBytes,
            success: success || partial,
            message: success ? "Cleaned successfully" : "Partially cleaned (\(allErrors.count) errors)",
            errors: allErrors,
            partialSuccess: partial
        )
    }

    // MARK: - Resolution Helpers

    /// Resolve `$GOMODCACHE`. Falls back to `~/go/pkg/mod` if `go env` is unavailable
    /// or returns nothing.
    private func resolveGoModCachePath() async -> String {
        if let result = try? await shell.run(Constants.goModCacheDirCommand), result.success {
            let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return Constants.goModuleCacheFallbackPath
    }

    /// Mail.app stores attachments per-version under `~/Library/Mail/V*/MailData/Attachments`
    /// (V8, V9, V10, …). Discover them at runtime so we don't hardcode a version.
    private func resolveMailAttachmentPaths() async -> [String] {
        guard await scanner.directoryExists(at: Constants.mailDataPath) else { return [] }
        let versionDirs = await scanner.childDirectories(of: Constants.mailDataPath) { name in
            name.hasPrefix("V") && name.count >= 2
        }
        var attachmentPaths: [String] = []
        for v in versionDirs {
            let candidate = (v as NSString).appendingPathComponent("MailData/Attachments")
            if await scanner.directoryExists(at: candidate) {
                attachmentPaths.append(candidate)
            }
        }
        return attachmentPaths
    }

    private func estimateScreenRecordingsSize() async -> Int64 {
        let threshold = Constants.largeScreenRecordingThreshold
        let matcher: @Sendable (URL, URLResourceValues) -> Bool = { url, values in
            Self.isScreenRecording(url: url, values: values, minSize: threshold)
        }

        var total: Int64 = 0
        for path in [Constants.desktopPath, Constants.documentsPath, Constants.moviesPath] {
            guard await scanner.directoryExists(at: path) else { continue }
            total += await scanner.filteredSize(at: path, matches: matcher)
        }
        return total
    }

    /// Match QuickTime/macOS screen recordings: `.mov` files whose name begins with
    /// "Screen Recording" or "Screenshot" and exceed the size threshold. Conservative
    /// enough that we don't sweep up unrelated user video footage.
    nonisolated private static func isScreenRecording(
        url: URL,
        values: URLResourceValues,
        minSize: Int64
    ) -> Bool {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let nameMatches = lower.hasPrefix("screen recording") || lower.hasPrefix("screenshot")
        guard nameMatches else { return false }
        guard lower.hasSuffix(".mov") || lower.hasSuffix(".mp4") else { return false }
        let size = Int64(values.fileSize ?? 0)
        return size >= minSize
    }

    nonisolated private static func fileIsOlderThan(_ cutoff: Date, values: URLResourceValues) -> Bool {
        // Prefer creationDate (when the file landed in Downloads), fall back to modification.
        let reference = values.creationDate ?? values.contentModificationDate
        guard let reference else { return false }
        return reference < cutoff
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
