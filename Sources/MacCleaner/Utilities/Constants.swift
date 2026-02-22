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

    // MARK: - Availability Check Commands

    static let brewCheckCommand = "which brew"
    static let npmCheckCommand = "which npm"
    static let pipCheckCommand = "which pip3"
    static let dockerCheckCommand = "docker info 2>/dev/null"
    static let xcodeSelectCheckCommand = "xcode-select -p 2>/dev/null"
    static let yarnCheckCommand = "which yarn"
    static let cocoapodsCheckCommand = "which pod"

    // MARK: - Size Estimation Commands

    static let brewCacheSizeCommand = "brew --cache 2>/dev/null"
    static let npmCacheSizeCommand = "npm cache ls 2>/dev/null | wc -l"
    static let pipCacheSizeCommand = "pip3 cache info 2>/dev/null"
    static let dockerDiskUsageCommand = "docker system df --format '{{.Size}}' 2>/dev/null"
    static let yarnCacheDirCommand = "yarn cache dir 2>/dev/null"

    static let cocoapodsCachePath: String = {
        NSHomeDirectory() + "/Library/Caches/CocoaPods"
    }()
}
