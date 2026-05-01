import Foundation
import AppKit

// MARK: - Leftover Categorization

enum LeftoverCategory: String, CaseIterable, Hashable {
    case mainBundle = "Application Bundle"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case logs = "Logs"
    case savedState = "Saved State"
    case launchAgents = "Launch Agents"
    case launchDaemons = "Launch Daemons"
    case groupContainers = "Group Containers"
    case containers = "Containers"
    case cookies = "Cookies"
    case webKit = "WebKit"
    case crashReports = "Crash Reports"
    case applicationScripts = "Application Scripts"
    case other = "Other"

    /// SF Symbol for the category badge.
    var icon: String {
        switch self {
        case .mainBundle:          return "app.fill"
        case .applicationSupport:  return "folder.fill"
        case .caches:              return "tray.full.fill"
        case .preferences:         return "slider.horizontal.3"
        case .logs:                return "doc.text.fill"
        case .savedState:          return "tray.and.arrow.down.fill"
        case .launchAgents:        return "bolt.badge.clock.fill"
        case .launchDaemons:       return "bolt.shield.fill"
        case .groupContainers:     return "shippingbox.fill"
        case .containers:          return "cube.box.fill"
        case .cookies:             return "circle.grid.cross.fill"
        case .webKit:              return "globe"
        case .crashReports:        return "exclamationmark.triangle.fill"
        case .applicationScripts:  return "scroll.fill"
        case .other:               return "questionmark.folder.fill"
        }
    }

    /// Stable display order: most user-meaningful first, system rarely-touched last.
    var sortPriority: Int {
        switch self {
        case .mainBundle:          return 0
        case .applicationSupport:  return 1
        case .containers:          return 2
        case .groupContainers:     return 3
        case .caches:              return 4
        case .preferences:         return 5
        case .savedState:          return 6
        case .logs:                return 7
        case .crashReports:        return 8
        case .cookies:             return 9
        case .webKit:              return 10
        case .applicationScripts:  return 11
        case .launchAgents:        return 12
        case .launchDaemons:       return 13
        case .other:               return 14
        }
    }
}

// MARK: - UninstallableApp

struct UninstallableApp: Identifiable, Hashable {
    /// Bundle identifier doubles as the stable ID. Falls back to the bundle URL
    /// for the rare case Info.plist is missing CFBundleIdentifier.
    let id: String
    let bundleID: String
    let name: String
    let version: String?
    let bundleURL: URL
    let installedDate: Date?
    let mainAppSize: Int64

    /// Resolved lazily on the main thread via `NSWorkspace.shared.icon(forFile:)`.
    /// Not part of equality/hash — two apps at the same bundleURL are equal.
    var icon: NSImage?

    static func == (lhs: UninstallableApp, rhs: UninstallableApp) -> Bool {
        lhs.bundleURL == rhs.bundleURL && lhs.bundleID == rhs.bundleID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleURL)
        hasher.combine(bundleID)
    }
}

// MARK: - AppLeftoverFile

struct AppLeftoverFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let category: LeftoverCategory
    /// True when the path lives outside the user's home directory and requires
    /// administrator privileges to remove. Used by the UI to render a lock badge
    /// and by the service to route deletion through `runWithPrivileges`.
    let isSystemPath: Bool

    static func == (lhs: AppLeftoverFile, rhs: AppLeftoverFile) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - UninstallResult

struct UninstallResult: Identifiable {
    let id = UUID()
    let app: UninstallableApp
    let bytesFreed: Int64
    let filesRemoved: Int
    let errors: [FileCleanupError]

    var success: Bool { errors.isEmpty }
    var partialSuccess: Bool { !errors.isEmpty && bytesFreed > 0 }
}
