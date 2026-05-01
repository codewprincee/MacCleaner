import SwiftUI
import AppKit

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = CleanupViewModel()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appearance") private var appearance: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .onAppear { appDelegate.attachViewModel(viewModel) }
                .frame(
                    minWidth: Theme.Window.minWidth,
                    minHeight: Theme.Window.minHeight
                )
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: Theme.Window.defaultWidth,
            height: Theme.Window.defaultHeight
        )
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.canCheckForUpdates)

                Divider()

                Button("Rescan") {
                    Task { await viewModel.scanAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isScanning || viewModel.isCleaning)

                Button("Clean Selected") {
                    viewModel.requestCleanSelected()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!viewModel.hasSelectedCategories || viewModel.isScanning || viewModel.isCleaning)
            }
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

/// Top-level view that gates the main UI behind a one-time onboarding flow.
private struct RootView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        ZStack {
            ContentView()
                .opacity(hasSeenOnboarding ? 1 : 0)

            if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation(Theme.Motion.snappy) {
                        hasSeenOnboarding = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}

/// Persisted appearance preference for the Settings scene.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
