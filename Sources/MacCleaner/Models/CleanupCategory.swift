import Foundation

enum CleanupType: String, CaseIterable, Identifiable {
    // File System
    case userCaches = "User Caches"
    case systemLogs = "System Logs"
    case tempFiles = "Temp Files"
    case trash = "Trash"
    case downloadsOldFiles = "Old Downloads"
    case mailDownloads = "Mail Attachments"
    case iosBackups = "iOS Device Backups"
    case quicktimeRecordings = "Old Screen Recordings"

    // Xcode
    case xcodeDerivedData = "Xcode Derived Data"
    case xcodeDeviceSupport = "iOS Device Support"
    case xcodeSimulators = "iOS Simulators"
    case xcodeArchives = "Xcode Archives"

    // Browsers
    case safariCache = "Safari Cache"
    case chromeCache = "Chrome Cache"
    case braveCache = "Brave Cache"
    case arcCache = "Arc Cache"
    case edgeCache = "Edge Cache"
    case firefoxCache = "Firefox Cache"
    case vivaldiCache = "Vivaldi Cache"
    case operaCache = "Opera Cache"

    // Package Managers
    case homebrewCache = "Homebrew Cache"
    case npmCache = "npm Cache"
    case pipCache = "pip Cache"
    case yarnCache = "Yarn Cache"
    case cocoapodsCache = "CocoaPods Cache"
    case cargoCache = "Cargo Cache"
    case goModuleCache = "Go Module Cache"
    case condaCache = "Conda Cache"
    case bundlerCache = "Bundler / Gem Cache"
    case gradleCache = "Gradle Cache"
    case mavenCache = "Maven Cache"
    case composerCache = "Composer Cache"

    // System (requires admin)
    case systemCaches = "System Caches"
    case dnsCache = "DNS Cache"
    case diagnosticReports = "Diagnostic Reports"
    case crashReporter = "Crash Reporter Logs"
    case timeMachineLocalSnapshots = "Local Time Machine Snapshots"

    // Containers
    case dockerData = "Docker Data"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .userCaches: return "folder.badge.gearshape"
        case .systemLogs: return "doc.text"
        case .tempFiles: return "clock.arrow.circlepath"
        case .trash: return "trash"
        case .downloadsOldFiles: return "tray.and.arrow.down"
        case .mailDownloads: return "envelope"
        case .iosBackups: return "iphone.gen3"
        case .quicktimeRecordings: return "record.circle"
        case .xcodeDerivedData: return "hammer"
        case .xcodeDeviceSupport: return "iphone"
        case .xcodeSimulators: return "ipad.landscape"
        case .xcodeArchives: return "archivebox"
        case .safariCache: return "safari"
        case .chromeCache: return "globe"
        case .braveCache: return "shield.lefthalf.filled"
        case .arcCache: return "a.circle"
        case .edgeCache: return "e.square"
        case .firefoxCache: return "flame"
        case .vivaldiCache: return "v.square"
        case .operaCache: return "o.square"
        case .homebrewCache: return "mug"
        case .npmCache: return "shippingbox"
        case .pipCache: return "cube"
        case .yarnCache: return "shippingbox.fill"
        case .cocoapodsCache: return "cube.fill"
        case .cargoCache: return "shippingbox.circle"
        case .goModuleCache: return "g.circle"
        case .condaCache: return "leaf"
        case .bundlerCache: return "gem"
        case .gradleCache: return "g.square"
        case .mavenCache: return "m.square"
        case .composerCache: return "c.square"
        case .systemCaches: return "lock.shield"
        case .dnsCache: return "network"
        case .diagnosticReports: return "stethoscope"
        case .crashReporter: return "exclamationmark.triangle"
        case .timeMachineLocalSnapshots: return "clock.arrow.2.circlepath"
        case .dockerData: return "cube.box"
        }
    }

    var description: String {
        switch self {
        case .userCaches: return "~/Library/Caches"
        case .systemLogs: return "~/Library/Logs"
        case .tempFiles: return "/tmp and temp directories"
        case .trash: return "~/.Trash"
        case .downloadsOldFiles: return "Files in ~/Downloads older than 30 days"
        case .mailDownloads: return "Mail attachments cached on disk (requires Full Disk Access)"
        case .iosBackups: return "WARNING: Permanently deletes iPhone/iPad backups"
        case .quicktimeRecordings: return "Screen recordings over 100MB on Desktop, Documents, Movies"
        case .xcodeDerivedData: return "~/Library/Developer/Xcode/DerivedData"
        case .xcodeDeviceSupport: return "~/Library/Developer/Xcode/iOS DeviceSupport"
        case .xcodeSimulators: return "Remove unavailable simulators"
        case .xcodeArchives: return "~/Library/Developer/Xcode/Archives"
        case .safariCache: return "Safari browser cache"
        case .chromeCache: return "Chrome browser cache"
        case .braveCache: return "Brave browser cache"
        case .arcCache: return "Arc browser cache"
        case .edgeCache: return "Microsoft Edge browser cache"
        case .firefoxCache: return "Firefox browser cache (per profile)"
        case .vivaldiCache: return "Vivaldi browser cache"
        case .operaCache: return "Opera browser cache"
        case .homebrewCache: return "Homebrew downloads"
        case .npmCache: return "npm package cache"
        case .pipCache: return "pip package cache"
        case .yarnCache: return "Yarn package cache"
        case .cocoapodsCache: return "CocoaPods spec & download cache"
        case .cargoCache: return "Rust cargo registry cache (preserves index)"
        case .goModuleCache: return "Go module download cache"
        case .condaCache: return "Conda package cache"
        case .bundlerCache: return "Ruby bundler & gem download cache"
        case .gradleCache: return "Gradle build cache"
        case .mavenCache: return "WARNING: Maven repository — re-downloads on next build"
        case .composerCache: return "PHP Composer download cache"
        case .systemCaches: return "/Library/Caches (requires admin)"
        case .dnsCache: return "Flush DNS resolver cache (requires admin)"
        case .diagnosticReports: return "System & user diagnostic reports"
        case .crashReporter: return "System & user crash reports"
        case .timeMachineLocalSnapshots: return "Local Time Machine snapshots (purgeable space)"
        case .dockerData: return "All unused Docker data"
        }
    }

    var requiresElevation: Bool {
        switch self {
        case .systemCaches, .dnsCache,
             .diagnosticReports, .crashReporter, .timeMachineLocalSnapshots:
            return true
        default:
            return false
        }
    }

    var usesShellCommand: Bool {
        switch self {
        case .homebrewCache, .npmCache, .pipCache, .yarnCache,
             .cocoapodsCache, .dockerData, .xcodeSimulators,
             .systemCaches, .dnsCache,
             .cargoCache, .goModuleCache, .condaCache,
             .timeMachineLocalSnapshots:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class CleanupCategory: ObservableObject, Identifiable {
    let type: CleanupType
    @Published var isSelected: Bool = true
    @Published var estimatedSize: Int64 = 0
    @Published var isScanning: Bool = false
    @Published var isAvailable: Bool = true
    @Published var isCleaning: Bool = false
    @Published var unavailableReason: String?

    nonisolated var id: String { type.id }

    init(type: CleanupType) {
        self.type = type
    }
}
