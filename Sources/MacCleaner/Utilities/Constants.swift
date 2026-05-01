import Foundation

enum Constants {
    // MARK: - Directory Paths

    static let userCachesPath: String = {
        NSHomeDirectory() + "/Library/Caches"
    }()

    static let systemLogsPath: String = {
        NSHomeDirectory() + "/Library/Logs"
    }()

    static let xcodeDerivedDataPath: String = {
        NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
    }()

    static let xcodeDeviceSupportPath: String = {
        NSHomeDirectory() + "/Library/Developer/Xcode/iOS DeviceSupport"
    }()

    static let xcodeArchivesPath: String = {
        NSHomeDirectory() + "/Library/Developer/Xcode/Archives"
    }()

    static let safariCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/com.apple.Safari"
    }()

    static let chromeCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/Google/Chrome"
    }()

    static let trashPath: String = {
        NSHomeDirectory() + "/.Trash"
    }()

    static let tempPath = "/tmp"
    static let systemCachesPath = "/Library/Caches"

    // MARK: - File System (additional)

    static let downloadsPath: String = {
        NSHomeDirectory() + "/Downloads"
    }()

    static let documentsPath: String = {
        NSHomeDirectory() + "/Documents"
    }()

    static let desktopPath: String = {
        NSHomeDirectory() + "/Desktop"
    }()

    static let moviesPath: String = {
        NSHomeDirectory() + "/Movies"
    }()

    /// Sandboxed Mail downloads (the modern Mail.app container).
    static let mailContainerDownloadsPath: String = {
        NSHomeDirectory() + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
    }()

    /// Legacy / non-sandboxed mail data root. The actual attachment dirs live under
    /// `V*/MailData/Attachments` which we discover at runtime.
    static let mailDataPath: String = {
        NSHomeDirectory() + "/Library/Mail"
    }()

    /// Finder & iTunes/Apple Devices store iOS device backups here.
    static let iosBackupsPath: String = {
        NSHomeDirectory() + "/Library/Application Support/MobileSync/Backup"
    }()

    /// File-age threshold for "old" downloads (30 days, in seconds).
    static let oldDownloadsAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// Minimum size (bytes) for a screen recording to be considered "old/large".
    static let largeScreenRecordingThreshold: Int64 = 100 * 1024 * 1024

    // MARK: - Browsers (additional)

    static let braveCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/BraveSoftware/Brave-Browser"
    }()

    /// Arc historically used two bundle IDs; both directories are checked.
    static let arcCachePathPrimary: String = {
        NSHomeDirectory() + "/Library/Caches/Company.ThePinarParade.Arc"
    }()

    static let arcCachePathSecondary: String = {
        NSHomeDirectory() + "/Library/Caches/com.thebrowser.Browser"
    }()

    static let edgeCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/Microsoft Edge"
    }()

    /// Firefox stores per-profile caches under `Profiles/`. We clean each profile's
    /// `cache2` (and similar) dirs by clearing the contents of this directory.
    static let firefoxCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/Firefox/Profiles"
    }()

    static let vivaldiCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/com.vivaldi.Vivaldi"
    }()

    static let operaCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/com.operasoftware.Opera"
    }()

    // MARK: - Package Managers (additional)

    static let cargoRegistryPath: String = {
        NSHomeDirectory() + "/.cargo/registry"
    }()

    static let cargoGitPath: String = {
        NSHomeDirectory() + "/.cargo/git"
    }()

    /// Cargo registry subdirs that are SAFE to delete. The `index` subdir is the
    /// registry crate index — deleting it forces a slow re-download on next build,
    /// so it is intentionally excluded.
    static let cargoRegistryCleanableSubdirs: [String] = ["cache", "src"]

    /// Fallback Go module cache when `go env GOMODCACHE` cannot be resolved.
    static let goModuleCacheFallbackPath: String = {
        NSHomeDirectory() + "/go/pkg/mod"
    }()

    static let condaCachePaths: [String] = [
        NSHomeDirectory() + "/.conda/pkgs",
        NSHomeDirectory() + "/anaconda3/pkgs",
        NSHomeDirectory() + "/miniconda3/pkgs",
    ]

    static let bundlerCachePaths: [String] = [
        NSHomeDirectory() + "/.bundle/cache",
        NSHomeDirectory() + "/.gem/cache",
    ]

    static let gradleCachePath: String = {
        NSHomeDirectory() + "/.gradle/caches"
    }()

    static let mavenRepositoryPath: String = {
        NSHomeDirectory() + "/.m2/repository"
    }()

    static let composerCachePaths: [String] = [
        NSHomeDirectory() + "/.composer/cache",
        NSHomeDirectory() + "/Library/Caches/composer",
    ]

    // MARK: - System (additional)

    static let userDiagnosticReportsPath: String = {
        NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
    }()

    static let systemDiagnosticReportsPath = "/Library/Logs/DiagnosticReports"

    static let userCrashReporterPath: String = {
        NSHomeDirectory() + "/Library/Logs/CrashReporter"
    }()

    static let systemCrashReporterPath = "/Library/Logs/CrashReporter"

    // MARK: - Shell Commands

    static let shellPath = "/bin/zsh"
    static let shellArgs = ["-l", "-c"]

    static let brewCleanupCommand = "brew cleanup --prune=all 2>&1"
    static let npmCacheCleanCommand = "npm cache clean --force 2>&1"
    static let pipCachePurgeCommand = "pip3 cache purge 2>&1"
    static let dockerPruneCommand = "docker system prune -a --volumes -f 2>&1"
    static let xcodeSimulatorsCleanCommand = "xcrun simctl delete unavailable 2>&1"
    static let yarnCacheCleanCommand = "yarn cache clean 2>&1"
    static let cocoapodsCacheCleanCommand = "pod cache clean --all --no-ansi 2>&1"
    static let dnsFlushCommand = "dscacheutil -flushcache && killall -HUP mDNSResponder"

    // Package manager (additional) commands
    /// Use `cargo cache --autoclean` if the `cargo-cache` plugin is installed.
    /// Caller falls back to filesystem cleanup of `registry/cache` and `registry/src`.
    static let cargoAutocleanCommand = "cargo cache --autoclean 2>&1"
    static let cargoAutocleanCheckCommand = "cargo cache --version 2>/dev/null"
    static let goModCleanCommand = "go clean -modcache 2>&1"
    static let goModCacheDirCommand = "go env GOMODCACHE 2>/dev/null"
    static let condaCleanCommand = "conda clean -a -y 2>&1"

    /// Force-delete every local Time Machine snapshot via tmutil. The huge integer is
    /// the "purge amount" required by tmutil; with urgency 4 this aggressively removes
    /// ALL local snapshots regardless of age.
    static let timeMachineThinSnapshotsCommand = "tmutil thinlocalsnapshots / 999999999999 4 2>&1"

    // MARK: - Availability Check Commands

    static let brewCheckCommand = "which brew"
    static let npmCheckCommand = "which npm"
    static let pipCheckCommand = "which pip3"
    static let dockerCheckCommand = "docker info 2>/dev/null"
    static let xcodeSelectCheckCommand = "xcode-select -p 2>/dev/null"
    static let yarnCheckCommand = "which yarn"
    static let cocoapodsCheckCommand = "which pod"
    static let cargoCheckCommand = "which cargo"
    static let goCheckCommand = "which go"
    static let condaCheckCommand = "which conda"
    static let bundleCheckCommand = "which bundle"
    static let gemCheckCommand = "which gem"

    // MARK: - Size Estimation Commands

    static let brewCacheSizeCommand = "brew --cache 2>/dev/null"
    static let dockerDiskUsageCommand = "docker system df --format '{{.Size}}' 2>/dev/null"
    static let yarnCacheDirCommand = "yarn cache dir 2>/dev/null"

    static let cocoapodsCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/CocoaPods"
    }()
}
