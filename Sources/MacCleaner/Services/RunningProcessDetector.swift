import Foundation
import AppKit

/// Reports whether apps that hold caches we want to clean are currently running.
/// Cleaning the cache of a running app can corrupt its profile/state, so we use this
/// to refuse or warn before destructive operations.
enum RunningProcessDetector {
    static func isRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleIdentifier
        }
    }

    /// Apps whose cache cleanup is unsafe while they are running.
    /// Returns the set of bundle IDs that are currently running and would be impacted.
    static func conflictingApps(for type: CleanupType) -> [ConflictingApp] {
        let candidates: [ConflictingApp]
        switch type {
        case .safariCache:
            candidates = [.safari]
        case .chromeCache:
            candidates = [.chrome]
        case .braveCache:
            candidates = [.brave]
        case .arcCache:
            candidates = [.arc]
        case .edgeCache:
            candidates = [.edge]
        case .firefoxCache:
            candidates = [.firefox]
        case .vivaldiCache:
            candidates = [.vivaldi]
        case .operaCache:
            candidates = [.opera]
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .xcodeSimulators:
            candidates = [.xcode]
        case .userCaches, .systemCaches:
            // Cleaning ~/Library/Caches while heavyweight apps run isn't catastrophic,
            // but it does cause noticeable transient slowdowns. Surface the most common
            // offenders so the user can quit them first.
            candidates = [.safari, .chrome, .xcode, .slack, .spotify]
        default:
            candidates = []
        }
        return candidates.filter { isRunning(bundleIdentifier: $0.bundleID) }
    }
}

struct ConflictingApp: Identifiable, Hashable {
    let id: String        // bundle id
    let displayName: String
    var bundleID: String { id }

    static let safari   = ConflictingApp(id: "com.apple.Safari", displayName: "Safari")
    static let chrome   = ConflictingApp(id: "com.google.Chrome", displayName: "Google Chrome")
    static let brave    = ConflictingApp(id: "com.brave.Browser", displayName: "Brave")
    static let arc      = ConflictingApp(id: "company.thebrowser.Browser", displayName: "Arc")
    static let edge     = ConflictingApp(id: "com.microsoft.edgemac", displayName: "Microsoft Edge")
    static let firefox  = ConflictingApp(id: "org.mozilla.firefox", displayName: "Firefox")
    static let vivaldi  = ConflictingApp(id: "com.vivaldi.Vivaldi", displayName: "Vivaldi")
    static let opera    = ConflictingApp(id: "com.operasoftware.Opera", displayName: "Opera")
    static let xcode    = ConflictingApp(id: "com.apple.dt.Xcode", displayName: "Xcode")
    static let slack    = ConflictingApp(id: "com.tinyspeck.slackmacgap", displayName: "Slack")
    static let spotify  = ConflictingApp(id: "com.spotify.client", displayName: "Spotify")
}
