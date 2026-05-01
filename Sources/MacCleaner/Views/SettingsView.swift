import SwiftUI
import UserNotifications

/// Native macOS-style preferences. Tabbed: General / Cleaning / Notifications / About.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }

            CleaningSettings()
                .tabItem { Label("Cleaning", systemImage: "sparkles") }

            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }

            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage("menuBarShowSize") private var menuBarShowSize = false
    @AppStorage("menuBarPollSeconds") private var menuBarPollSeconds: Double = 60

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $menuBarEnabled)
                Toggle("Show used size next to icon", isOn: $menuBarShowSize)
                    .disabled(!menuBarEnabled)
                LabeledContent("Refresh interval") {
                    HStack {
                        Slider(value: $menuBarPollSeconds, in: 30...600, step: 30)
                            .frame(width: 160)
                        Text("\(Int(menuBarPollSeconds))s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!menuBarEnabled)
                Text("The menu bar icon shows your disk pressure at a glance and offers a one-click Quick Clean.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Onboarding") {
                LabeledContent("First-launch tour") {
                    Button("Reset onboarding") {
                        hasSeenOnboarding = false
                    }
                    .disabled(!hasSeenOnboarding)
                }
                Text("Use this if you want to revisit the welcome flow on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cleaning

private struct CleaningSettings: View {
    @AppStorage("confirmBeforeCleaning") private var confirmBeforeCleaning = true
    @AppStorage("autoSelectAvailable")  private var autoSelectAvailable = true
    @AppStorage("playSoundOnComplete")  private var playSoundOnComplete = false

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Confirm before cleaning", isOn: $confirmBeforeCleaning)
                Text("Show a summary sheet listing every category that will be cleaned, with conflict warnings for running apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Toggle("Auto-select all available categories on scan", isOn: $autoSelectAvailable)
                Toggle("Play sound when cleanup finishes", isOn: $playSoundOnComplete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusLabel)
                            .foregroundStyle(.secondary)
                    }
                }

                if status == .notDetermined {
                    Button("Request permission") {
                        Task {
                            _ = try? await UNUserNotificationCenter
                                .current()
                                .requestAuthorization(options: [.alert, .sound])
                            await refresh()
                        }
                    }
                } else if status == .denied {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Section("What we notify about") {
                Text("Storage critically low (under 10% free space). That's it. No marketing, no upsell, no engagement nudges.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private var statusColor: Color {
        switch status {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .orange
        }
    }

    private var statusLabel: String {
        switch status {
        case .authorized:    return "Allowed"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        case .denied:        return "Denied"
        case .notDetermined: return "Not requested"
        @unknown default:    return "Unknown"
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { status = settings.authorizationStatus }
    }
}

// MARK: - About

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.brandHero)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 4) {
                Text("MacCleaner")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Version \(version) (\(build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A focused, privacy-respecting cleanup tool for macOS. Open source and local-only.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            HStack(spacing: Theme.Spacing.md) {
                Link(destination: URL(string: "https://github.com")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://opensource.org/license/mit")!) {
                    Label("License", systemImage: "doc.text")
                }
            }
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }
}
