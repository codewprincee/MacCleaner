import Foundation
import Sparkle

/// Sparkle 2 wrapper. Stays completely dormant unless the bundle is configured
/// for production updates — that means a non-empty `SUFeedURL` AND a non-empty
/// `SUPublicEDKey` in Info.plist. Locally-built dev installs ship with an empty
/// `SUPublicEDKey`, so Sparkle never starts and the "Check for Updates…" menu
/// item is disabled. This avoids the runtime alert "The updater failed to start"
/// that Sparkle raises when it can't validate its own signing posture.
///
/// To enable in a release build:
///   1. Generate an EdDSA keypair with Sparkle's `generate_keys` tool.
///   2. Put the public key (base64) into `SUPublicEDKey` in Info.plist.
///   3. Sign your appcast with the private key via `generate_appcast`.
///   4. Code-sign the app with a real Developer ID (not ad-hoc).
@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    private let updaterController: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = false

    override init() {
        if Self.isProductionConfigured {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.updaterController = controller
            super.init()
            self.canCheckForUpdates = controller.updater.canCheckForUpdates
        } else {
            self.updaterController = nil
            super.init()
            self.canCheckForUpdates = false
        }
    }

    /// True only when a feed URL and a public signing key are both present.
    /// We don't even instantiate `SPUStandardUpdaterController` otherwise,
    /// because its init alone surfaces user-facing alerts on misconfiguration.
    private static var isProductionConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !feed.isEmpty, !key.isEmpty else { return false }
        guard let url = URL(string: feed), url.scheme == "https" else { return false }
        return true
    }

    /// Trigger a user-visible update check. No-op when not production-configured.
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
