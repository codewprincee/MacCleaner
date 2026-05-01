import AppKit
import SwiftUI

/// Hosts the `NSStatusItem` lifecycle alongside the SwiftUI scene.
///
/// We don't pre-build the controller in `applicationDidFinishLaunching` because
/// the `CleanupViewModel` is owned by the `App` struct (so its identity
/// matches the `WindowGroup`'s `@StateObject`). Instead, the SwiftUI side calls
/// `attachViewModel(_:)` from `.onAppear`, which is guaranteed to fire before
/// the user can interact with anything. After that point the controller is
/// installed with the same instance both surfaces share.
@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var menuBarController: MenuBarController?
    private weak var attachedViewModel: CleanupViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally empty. The status item is created in `attachViewModel`
        // once the SwiftUI WindowGroup hands us the shared view model.
        // Keeping `LSUIElement` off (the regular window stays visible) is also
        // why we don't need to do anything here at launch.
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.shutdown()
    }

    /// Wire up the controller against the shared `CleanupViewModel`. Idempotent —
    /// SwiftUI may re-fire `.onAppear` for the same instance and we should not
    /// install a second status item.
    func attachViewModel(_ viewModel: CleanupViewModel) {
        if attachedViewModel === viewModel, menuBarController != nil { return }
        attachedViewModel = viewModel

        let controller = MenuBarController(viewModel: viewModel)
        menuBarController = controller
        controller.bootstrap()
    }
}
