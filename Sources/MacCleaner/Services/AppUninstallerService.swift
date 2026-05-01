import Foundation
import AppKit

/// Discovers installed third-party apps and finds every leftover file they have
/// scattered across `~/Library`, `/Library`, sandbox containers, launch agents,
/// crash reports, etc. Then performs a two-pass deletion: user-writable items
/// via `FileManager`, system paths via authenticated `osascript`.
actor AppUninstallerService {
    private let fileManager = FileManager.default
    private let shell = ShellCommandRunner()

    // MARK: - Bundles to refuse to uninstall

    /// We will not uninstall ourselves — that would yank the rug mid-operation
    /// and leave the user with a half-deleted Trash bin entry.
    private static let selfBundleID = "com.codewprince.MacCleaner"

    /// Apple system bundle prefix. We never touch anything matching this AND
    /// living under `/System` or shipped with the OS.
    private static let appleBundlePrefix = "com.apple."

    // MARK: - Search roots for installed apps

    /// Locations we enumerate when discovering installed apps. `/System/Applications`
    /// is intentionally excluded — those bundles are SIP-protected and trying to
    /// uninstall them is at best a no-op and at worst breaks the OS.
    private static let appSearchRoots: [String] = [
        "/Applications",
        "/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    // MARK: - Discovery

    /// Walk the app search roots, parse each `.app`'s Info.plist, and return a
    /// sorted list of uninstallable apps. Apple-signed system apps are filtered
    /// out, as is MacCleaner itself.
    func discoverInstalledApps() async -> [UninstallableApp] {
        var seen: Set<URL> = []
        var apps: [UninstallableApp] = []

        for root in Self.appSearchRoots {
            guard fileManager.fileExists(atPath: root) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: root) else { continue }

            for name in contents where name.hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(name)
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                if seen.contains(url) { continue }
                seen.insert(url)

                guard let app = await Self.makeApp(at: url) else { continue }

                // Skip macOS-bundled or our own app.
                if app.bundleID == Self.selfBundleID { continue }
                if Self.isAppleSystemApp(bundleID: app.bundleID, url: url) { continue }

                apps.append(app)
            }
        }

        return apps.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Leftover discovery

    /// Find every file/directory tied to `app` across the user-library, system
    /// library, sandbox containers, and crash report locations. Returns a sorted
    /// list grouped by category, then by size descending within each group.
    func findLeftovers(for app: UninstallableApp) async -> [AppLeftoverFile] {
        let candidates = Self.candidatePaths(for: app)
        var leftovers: [AppLeftoverFile] = []
        var seenURLs: Set<URL> = []

        for candidate in candidates {
            // Path-traversal defense: every resolved path must live under a
            // sanctioned root. This guards against malicious bundleIDs ("../etc/passwd")
            // and rogue symlinks.
            guard let resolved = Self.safelyResolve(candidate.path) else { continue }
            if seenURLs.contains(resolved) { continue }

            guard fileManager.fileExists(atPath: resolved.path) else { continue }
            seenURLs.insert(resolved)

            let size = FileSystemScanner.computeSize(at: resolved.path)
            // Don't surface zero-byte directories — they're noise. But always
            // surface the main bundle even at 0 bytes (shouldn't happen, but
            // we want the user to see *something* if it does).
            if size == 0 && candidate.category != .mainBundle { continue }

            leftovers.append(AppLeftoverFile(
                url: resolved,
                size: size,
                category: candidate.category,
                isSystemPath: candidate.isSystemPath
            ))
        }

        // Glob-style scans (LaunchAgents directory, DiagnosticReports, etc.) where
        // we have to enumerate a directory and pattern-match by filename.
        leftovers.append(contentsOf: await scanDirectoryGlobs(for: app, exclude: seenURLs))

        // Final sort: priority bucket, then size desc.
        leftovers.sort { lhs, rhs in
            if lhs.category.sortPriority != rhs.category.sortPriority {
                return lhs.category.sortPriority < rhs.category.sortPriority
            }
            return lhs.size > rhs.size
        }
        return leftovers
    }

    // MARK: - Uninstall

    /// Two-pass deletion. The main app bundle is sent to Trash (recoverable).
    /// User-writable leftovers are removed in-process via `FileManager`. System
    /// paths (`/Library/LaunchDaemons/...`) are deleted in a single authenticated
    /// `osascript` invocation so the user is only prompted for their password once.
    func uninstall(_ app: UninstallableApp, leftovers: [AppLeftoverFile]) async -> UninstallResult {
        // Refuse to uninstall ourselves — defense in depth, even though the UI
        // already filters us out of the list.
        if app.bundleID == Self.selfBundleID {
            return UninstallResult(
                app: app,
                bytesFreed: 0,
                filesRemoved: 0,
                errors: [FileCleanupError(path: app.bundleURL.path,
                                          reason: "MacCleaner cannot uninstall itself")]
            )
        }

        var bytesFreed: Int64 = 0
        var filesRemoved = 0
        var errors: [FileCleanupError] = []

        var userPaths: [AppLeftoverFile] = []
        var systemPaths: [AppLeftoverFile] = []
        var bundleEntry: AppLeftoverFile?

        for item in leftovers {
            if item.category == .mainBundle {
                bundleEntry = item
            } else if item.isSystemPath {
                systemPaths.append(item)
            } else {
                userPaths.append(item)
            }
        }

        // Pass 1: user-writable removals via FileManager.
        for file in userPaths {
            // Re-validate at delete time — the path could have been swapped for
            // a symlink between scan and deletion.
            guard let safe = Self.safelyResolve(file.url.path) else {
                errors.append(FileCleanupError(
                    path: file.url.path,
                    reason: "Path failed safety validation"
                ))
                continue
            }
            do {
                try fileManager.removeItem(at: safe)
                bytesFreed += file.size
                filesRemoved += 1
            } catch {
                errors.append(FileCleanupError(
                    path: file.url.path,
                    reason: error.localizedDescription
                ))
            }
        }

        // Pass 2: system-path removals batched into a single privileged call.
        if !systemPaths.isEmpty {
            let quoted = systemPaths
                .compactMap { Self.safelyResolve($0.url.path)?.path }
                .map { ShellCommandRunner.shellQuote($0) }
                .joined(separator: " ")

            // `rm -rf -- ...` is the right primitive here: we have already
            // validated each path lives under /Library or /var. `--` defuses any
            // path that begins with a hyphen.
            let command = "/bin/rm -rf -- \(quoted) 2>&1"

            do {
                let result = try await shell.runWithPrivileges(command)
                if result.success {
                    for file in systemPaths {
                        bytesFreed += file.size
                        filesRemoved += 1
                    }
                } else {
                    errors.append(FileCleanupError(
                        path: "system paths",
                        reason: result.output.isEmpty ? "Privileged delete failed" : result.output
                    ))
                }
            } catch ShellCommandRunner.ShellError.authorizationDenied {
                errors.append(FileCleanupError(
                    path: "system paths",
                    reason: "Administrator authorization denied"
                ))
            } catch {
                errors.append(FileCleanupError(
                    path: "system paths",
                    reason: error.localizedDescription
                ))
            }
        }

        // Pass 3: main bundle goes to Trash (recoverable). Always last so that
        // if any leftover-deletion failed we still own up to the bundle being
        // intact when we report errors.
        if let bundle = bundleEntry {
            let result = await Self.moveToTrash(bundle.url)
            switch result {
            case .success:
                bytesFreed += bundle.size
                filesRemoved += 1
            case .failure(let err):
                errors.append(err)
            }
        }

        return UninstallResult(
            app: app,
            bytesFreed: bytesFreed,
            filesRemoved: filesRemoved,
            errors: errors
        )
    }

    // MARK: - Helpers

    /// Build an `UninstallableApp` from a `.app` bundle URL by reading its
    /// Info.plist. Returns nil for malformed bundles.
    private static func makeApp(at url: URL) async -> UninstallableApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]

        let bundleID = info["CFBundleIdentifier"] as? String
            ?? bundle.bundleIdentifier
            ?? url.deletingPathExtension().lastPathComponent

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        let installedDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date

        let size = FileSystemScanner.computeSize(at: url.path)

        // Resolve icon on the main thread — NSWorkspace must be touched there.
        let icon = await MainActor.run { NSWorkspace.shared.icon(forFile: url.path) }

        var app = UninstallableApp(
            id: bundleID,
            bundleID: bundleID,
            name: name,
            version: version,
            bundleURL: url,
            installedDate: installedDate,
            mainAppSize: size,
            icon: nil
        )
        app.icon = icon
        return app
    }

    /// True when the bundle is part of macOS itself. We skip these so users
    /// don't accidentally try to uninstall Mail or Safari (it would fail anyway).
    private static func isAppleSystemApp(bundleID: String, url: URL) -> Bool {
        guard bundleID.hasPrefix(appleBundlePrefix) else { return false }
        let path = url.path
        if path.hasPrefix("/System/") { return true }
        // Apple ships a number of first-party apps in /Applications that ARE
        // technically uninstallable (Pages, Numbers, Keynote, Xcode), so we
        // don't blanket-filter every com.apple bundle in /Applications.
        let stickyAppleBundles: Set<String> = [
            "com.apple.mail",
            "com.apple.Safari",
            "com.apple.FaceTime",
            "com.apple.AppStore",
            "com.apple.Music",
            "com.apple.TV",
            "com.apple.Maps",
            "com.apple.Photos",
            "com.apple.iCal",
            "com.apple.AddressBook",
            "com.apple.reminders",
            "com.apple.Notes",
            "com.apple.Preview",
            "com.apple.systempreferences",
            "com.apple.finder"
        ]
        return stickyAppleBundles.contains(bundleID)
    }

    // MARK: - Path candidates

    private struct Candidate {
        let path: String
        let category: LeftoverCategory
        let isSystemPath: Bool
    }

    /// Build the static, exact-match list of candidate paths for an app. The
    /// glob-based searches (e.g. `~/Library/LaunchAgents/*.plist` whose `Label`
    /// matches the bundleID) live in `scanDirectoryGlobs`.
    private static func candidatePaths(for app: UninstallableApp) -> [Candidate] {
        let home = NSHomeDirectory()
        let bid = app.bundleID
        let name = app.name

        // Sanitized name variants for filesystem-friendly lookups.
        let sanitizedName = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        var candidates: [Candidate] = []

        // Main bundle — always category .mainBundle.
        candidates.append(Candidate(
            path: app.bundleURL.path,
            category: .mainBundle,
            isSystemPath: app.bundleURL.path.hasPrefix("/Applications")
        ))

        // ~/Library/Application Support (both bundleID and name forms).
        for base in ["\(home)/Library/Application Support/\(bid)",
                     "\(home)/Library/Application Support/\(sanitizedName)"] {
            candidates.append(Candidate(path: base, category: .applicationSupport, isSystemPath: false))
        }

        // ~/Library/Caches.
        for base in ["\(home)/Library/Caches/\(bid)",
                     "\(home)/Library/Caches/\(sanitizedName)"] {
            candidates.append(Candidate(path: base, category: .caches, isSystemPath: false))
        }

        // ~/Library/Preferences/<bundleID>.plist.
        candidates.append(Candidate(
            path: "\(home)/Library/Preferences/\(bid).plist",
            category: .preferences,
            isSystemPath: false
        ))
        // ByHost-scoped preferences.
        candidates.append(Candidate(
            path: "\(home)/Library/Preferences/ByHost/\(bid).plist",
            category: .preferences,
            isSystemPath: false
        ))

        // ~/Library/Logs.
        for base in ["\(home)/Library/Logs/\(bid)",
                     "\(home)/Library/Logs/\(sanitizedName)"] {
            candidates.append(Candidate(path: base, category: .logs, isSystemPath: false))
        }

        // Saved Application State.
        candidates.append(Candidate(
            path: "\(home)/Library/Saved Application State/\(bid).savedState",
            category: .savedState,
            isSystemPath: false
        ))

        // Launch Agents (user).
        candidates.append(Candidate(
            path: "\(home)/Library/LaunchAgents/\(bid).plist",
            category: .launchAgents,
            isSystemPath: false
        ))

        // Launch Agents / Daemons (system) — flagged for privileged delete.
        candidates.append(Candidate(
            path: "/Library/LaunchAgents/\(bid).plist",
            category: .launchAgents,
            isSystemPath: true
        ))
        candidates.append(Candidate(
            path: "/Library/LaunchDaemons/\(bid).plist",
            category: .launchDaemons,
            isSystemPath: true
        ))

        // Application Support (system).
        candidates.append(Candidate(
            path: "/Library/Application Support/\(bid)",
            category: .applicationSupport,
            isSystemPath: true
        ))

        // Group Containers (exact + group-prefixed).
        candidates.append(Candidate(
            path: "\(home)/Library/Group Containers/\(bid)",
            category: .groupContainers,
            isSystemPath: false
        ))
        candidates.append(Candidate(
            path: "\(home)/Library/Group Containers/group.\(bid)",
            category: .groupContainers,
            isSystemPath: false
        ))

        // Sandboxed container.
        candidates.append(Candidate(
            path: "\(home)/Library/Containers/\(bid)",
            category: .containers,
            isSystemPath: false
        ))

        // Cookies.
        candidates.append(Candidate(
            path: "\(home)/Library/Cookies/\(bid).binarycookies",
            category: .cookies,
            isSystemPath: false
        ))

        // WebKit storage.
        candidates.append(Candidate(
            path: "\(home)/Library/WebKit/\(bid)",
            category: .webKit,
            isSystemPath: false
        ))

        // HTTP storages (modern Safari/WebKit storage).
        candidates.append(Candidate(
            path: "\(home)/Library/HTTPStorages/\(bid)",
            category: .cookies,
            isSystemPath: false
        ))
        candidates.append(Candidate(
            path: "\(home)/Library/HTTPStorages/\(bid).binarycookies",
            category: .cookies,
            isSystemPath: false
        ))

        // Application Scripts (sandboxed app helper scripts).
        candidates.append(Candidate(
            path: "\(home)/Library/Application Scripts/\(bid)",
            category: .applicationScripts,
            isSystemPath: false
        ))

        return candidates
    }

    // MARK: - Glob scans

    /// Pattern-based searches that can't be expressed as exact paths. These
    /// enumerate a parent directory and pick out items whose name matches our
    /// app. We deliberately keep the patterns conservative — false positives
    /// here lead to deleting the wrong app's data.
    private func scanDirectoryGlobs(for app: UninstallableApp, exclude: Set<URL>) async -> [AppLeftoverFile] {
        let home = NSHomeDirectory()
        let bid = app.bundleID
        let name = app.name
        var results: [AppLeftoverFile] = []
        var seen = exclude

        // Preferences with bundleID prefix (e.g. com.foo.Bar.LSSharedFileList.plist).
        results.append(contentsOf: enumeratePrefixed(
            in: "\(home)/Library/Preferences",
            prefix: "\(bid).",
            category: .preferences,
            isSystemPath: false,
            seen: &seen
        ))
        results.append(contentsOf: enumeratePrefixed(
            in: "\(home)/Library/Preferences/ByHost",
            prefix: "\(bid).",
            category: .preferences,
            isSystemPath: false,
            seen: &seen
        ))

        // Group containers prefixed with the bundleID (e.g. group.com.foo.Bar.shared).
        results.append(contentsOf: enumeratePrefixed(
            in: "\(home)/Library/Group Containers",
            prefix: "\(bid).",
            category: .groupContainers,
            isSystemPath: false,
            seen: &seen
        ))

        // LaunchAgents whose Label matches the bundleID (slightly more expensive
        // — we have to peek at the plist).
        results.append(contentsOf: enumerateLaunchAgents(
            in: "\(home)/Library/LaunchAgents",
            matching: bid,
            category: .launchAgents,
            isSystemPath: false,
            seen: &seen
        ))

        // Crash reports — DiagnosticReports/<AppName>_<date>-<host>.crash/.ips.
        results.append(contentsOf: enumeratePrefixed(
            in: "\(home)/Library/Logs/DiagnosticReports",
            prefix: "\(name)_",
            category: .crashReports,
            isSystemPath: false,
            seen: &seen
        ))
        results.append(contentsOf: enumeratePrefixed(
            in: "/Library/Logs/DiagnosticReports",
            prefix: "\(name)_",
            category: .crashReports,
            isSystemPath: true,
            seen: &seen
        ))

        // Helpd-generated help bundles.
        results.append(contentsOf: enumeratePrefixed(
            in: "\(home)/Library/Caches/com.apple.helpd/Generated",
            prefix: bid,
            category: .caches,
            isSystemPath: false,
            seen: &seen
        ))

        return results
    }

    /// Walk `directory`, return entries whose filename starts with `prefix`.
    private func enumeratePrefixed(
        in directory: String,
        prefix: String,
        category: LeftoverCategory,
        isSystemPath: Bool,
        seen: inout Set<URL>
    ) -> [AppLeftoverFile] {
        guard fileManager.fileExists(atPath: directory) else { return [] }
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        var out: [AppLeftoverFile] = []

        for name in names where name.hasPrefix(prefix) {
            let path = (directory as NSString).appendingPathComponent(name)
            guard let resolved = Self.safelyResolve(path) else { continue }
            if seen.contains(resolved) { continue }
            seen.insert(resolved)

            let size = FileSystemScanner.computeSize(at: resolved.path)
            if size == 0 { continue }
            out.append(AppLeftoverFile(
                url: resolved,
                size: size,
                category: category,
                isSystemPath: isSystemPath
            ))
        }
        return out
    }

    /// Look at every plist in a LaunchAgents directory, parse it, and return
    /// any whose `Label` matches our bundleID. Catches third-party agents that
    /// don't follow the naming convention.
    private func enumerateLaunchAgents(
        in directory: String,
        matching bundleID: String,
        category: LeftoverCategory,
        isSystemPath: Bool,
        seen: inout Set<URL>
    ) -> [AppLeftoverFile] {
        guard fileManager.fileExists(atPath: directory) else { return [] }
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        var out: [AppLeftoverFile] = []

        for name in names where name.hasSuffix(".plist") {
            let path = (directory as NSString).appendingPathComponent(name)
            guard let resolved = Self.safelyResolve(path) else { continue }
            if seen.contains(resolved) { continue }

            // Read the plist and check its Label key.
            guard let data = try? Data(contentsOf: resolved),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let label = plist["Label"] as? String
            else { continue }

            if label == bundleID || label.hasPrefix("\(bundleID).") {
                seen.insert(resolved)
                let size = FileSystemScanner.computeSize(at: resolved.path)
                out.append(AppLeftoverFile(
                    url: resolved,
                    size: size,
                    category: category,
                    isSystemPath: isSystemPath
                ))
            }
        }
        return out
    }

    // MARK: - Path safety

    /// Resolve a path through symlinks and verify it lives under a sanctioned
    /// root (`$HOME`, `/Applications`, `/Library`, `/var`, `/private`). Returns
    /// nil if the resolution lands somewhere we should NOT touch — e.g. `/etc`
    /// or `/System` or a path that traversed `..` outside our roots.
    nonisolated static func safelyResolve(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let resolved = url.path

        // Guard against null bytes or empty strings.
        if resolved.isEmpty || resolved.contains("\0") { return nil }

        // Sanctioned roots. Note `/private` because macOS resolves /tmp -> /private/tmp
        // and /var -> /private/var. We're permissive on /Library because that's
        // exactly where LaunchAgents/LaunchDaemons live.
        let allowedPrefixes = [
            NSHomeDirectory() + "/",
            "/Applications/",
            "/Library/",
            "/private/var/folders/",
            "/private/tmp/",
            "/var/folders/",
            "/tmp/"
        ]

        // System directories we explicitly block even if a symlink lands there.
        let blockedPrefixes = [
            "/System/",
            "/usr/",
            "/bin/",
            "/sbin/",
            "/etc/",
            "/dev/"
        ]

        for blocked in blockedPrefixes {
            if resolved.hasPrefix(blocked) { return nil }
        }
        for allowed in allowedPrefixes {
            if resolved.hasPrefix(allowed) { return url }
        }
        // Special case: an exact-match /Applications without trailing slash.
        if resolved == "/Applications" { return nil }
        return nil
    }

    // MARK: - Trash helper

    /// Move the main bundle to Trash via `NSWorkspace.recycle`. Returns success
    /// or a structured error suitable for surfacing in the result UI.
    @MainActor
    private static func moveToTrash(_ url: URL) async -> Result<Void, FileCleanupError> {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error = error {
                    continuation.resume(returning: .failure(FileCleanupError(
                        path: url.path,
                        reason: error.localizedDescription
                    )))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }
}
