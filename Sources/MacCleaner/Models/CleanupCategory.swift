import Foundation

enum CleanupType: String, CaseIterable, Identifiable {
    // File System
    case userCaches = "User Caches"
    case systemLogs = "System Logs"
    case tempFiles = "Temp Files"
    case trash = "Trash"

    // Xcode
    case xcodeDerivedData = "Xcode Derived Data"
    case xcodeDeviceSupport = "iOS Device Support"
    case xcodeSimulators = "iOS Simulators"
    case xcodeArchives = "Xcode Archives"

    // Browsers
    case safariCache = "Safari Cache"
    case chromeCache = "Chrome Cache"

    // Package Managers
    case homebrewCache = "Homebrew Cache"
    case npmCache = "npm Cache"
    case pipCache = "pip Cache"
    case yarnCache = "Yarn Cache"
    case cocoapodsCache = "CocoaPods Cache"

    // System (requires admin)
    case systemCaches = "System Caches"
    case dnsCache = "DNS Cache"

    // Containers
    case dockerData = "Docker Data"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .userCaches: return "folder.badge.gearshape"
        case .systemLogs: return "doc.text"
        case .tempFiles: return "clock.arrow.circlepath"
        case .trash: return "trash"
        case .xcodeDerivedData: return "hammer"
        case .xcodeDeviceSupport: return "iphone"
        case .xcodeSimulators: return "ipad.landscape"
        case .xcodeArchives: return "archivebox"
        case .safariCache: return "safari"
        case .chromeCache: return "globe"
        case .homebrewCache: return "mug"
        case .npmCache: return "shippingbox"
        case .pipCache: return "cube"
        case .yarnCache: return "shippingbox.fill"
        case .cocoapodsCache: return "cube.fill"
        case .systemCaches: return "lock.shield"
        case .dnsCache: return "network"
        case .dockerData: return "cube.box"
        }
    }

    var description: String {
        switch self {
        case .userCaches: return "~/Library/Caches"
        case .systemLogs: return "~/Library/Logs"
        case .tempFiles: return "/tmp and temp directories"
        case .trash: return "~/.Trash"
        case .xcodeDerivedData: return "~/Library/Developer/Xcode/DerivedData"
        case .xcodeDeviceSupport: return "~/Library/Developer/Xcode/iOS DeviceSupport"
        case .xcodeSimulators: return "Remove unavailable simulators"
        case .xcodeArchives: return "~/Library/Developer/Xcode/Archives"
        case .safariCache: return "Safari browser cache"
        case .chromeCache: return "Chrome browser cache"
        case .homebrewCache: return "Homebrew downloads"
        case .npmCache: return "npm package cache"
        case .pipCache: return "pip package cache"
        case .yarnCache: return "Yarn package cache"
        case .cocoapodsCache: return "CocoaPods spec & download cache"
        case .systemCaches: return "/Library/Caches (requires admin)"
        case .dnsCache: return "Flush DNS resolver cache (requires admin)"
        case .dockerData: return "All unused Docker data"
        }
    }

    var requiresElevation: Bool {
        switch self {
        case .systemCaches, .dnsCache:
            return true
        default:
            return false
        }
    }

    var usesShellCommand: Bool {
        switch self {
        case .homebrewCache, .npmCache, .pipCache, .yarnCache,
             .cocoapodsCache, .dockerData, .xcodeSimulators,
             .systemCaches, .dnsCache:
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
