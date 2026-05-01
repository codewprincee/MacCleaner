import SwiftUI
import UserNotifications

/// Production-quality onboarding shown on first launch. Four pages: hero,
/// privacy, admin password, and notifications. Persists `hasSeenOnboarding`
/// once the user clicks "Get Started".
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page: Int = 0
    @State private var notificationsRequested = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4

    var body: some View {
        ZStack {
            // Layered backdrop — soft brand gradient, never garish.
            backdrop

            VStack(spacing: 0) {
                // Skip in top-trailing corner.
                HStack {
                    Spacer()
                    Button("Skip") { complete() }
                        .buttonStyle(.plain)
                        .font(.system(.callout).weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(Theme.Spacing.lg)
                        .accessibilityLabel("Skip onboarding")
                }

                Spacer(minLength: 0)

                // Page content.
                Group {
                    switch page {
                    case 0: heroPage
                    case 1: privacyPage
                    case 2: adminPage
                    default: notificationsPage
                    }
                }
                .frame(maxWidth: 560)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .id(page)

                Spacer(minLength: 0)

                // Indicator dots.
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: index == page ? 22 : 7, height: 7)
                            .animation(Theme.Motion.smooth, value: page)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
                .accessibilityHidden(true)

                // Nav buttons.
                HStack(spacing: Theme.Spacing.md) {
                    if page > 0 {
                        Button {
                            withAnimation(Theme.Motion.smooth) { page -= 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                                .font(.system(.body).weight(.medium))
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    }

                    Spacer()

                    Button {
                        if page == pageCount - 1 {
                            complete()
                        } else {
                            withAnimation(Theme.Motion.smooth) { page += 1 }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(page == pageCount - 1 ? "Get Started" : "Continue")
                            if page < pageCount - 1 {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.system(.body).weight(.semibold))
                        .frame(minWidth: 140)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pages

    private var heroPage: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Composed SF Symbols hero illustration.
            ZStack {
                Circle()
                    .fill(.brandHero.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: 4)

                Circle()
                    .strokeBorder(.brandSubtle.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 180, height: 180)

                Image(systemName: "internaldrive")
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(.brandHero)
                    .symbolRenderingMode(.hierarchical)

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                    .offset(x: 56, y: -54)
            }
            .frame(height: 220)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Reclaim space on your Mac")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)

                Text("MacCleaner finds and removes the cruft that piles up: caches, logs, derived data, and Docker volumes — without touching your real files.")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                FeatureBullet(icon: "folder.fill", tint: .blue, text: "User & system caches")
                FeatureBullet(icon: "hammer.fill", tint: .indigo, text: "Xcode derived data, archives, simulators")
                FeatureBullet(icon: "shippingbox.fill", tint: .orange, text: "Homebrew, npm, pip, Yarn, CocoaPods")
                FeatureBullet(icon: "cube.box.fill", tint: .teal, text: "Unused Docker images and volumes")
            }
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var privacyPage: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 160, height: 160)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Privacy first")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Everything happens on your Mac. No telemetry, no analytics, no data leaves this machine.")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("WE NEVER TOUCH")
                    .font(Theme.Typography.eyebrow)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                FeatureBullet(icon: "doc.fill", tint: .blue, text: "Your Documents, Desktop, or Downloads")
                FeatureBullet(icon: "photo.fill", tint: .pink, text: "Photos, music, or video libraries")
                FeatureBullet(icon: "envelope.fill", tint: .orange, text: "Mail or messaging data")
                FeatureBullet(icon: "key.fill", tint: .yellow, text: "Keychain or credentials")
            }
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var adminPage: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 160, height: 160)
                Image(systemName: "key.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Admin access")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("A few system-level cleanups (DNS cache, /Library/Caches) require your password — exactly the same prompt macOS uses for any privileged command.")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("You're prompted only for items that need it.")
                        .font(.callout)
                }
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("You can skip these categories at any time.")
                        .font(.callout)
                }
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("Your password is handled by macOS, never stored.")
                        .font(.callout)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
        }
    }

    private var notificationsPage: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 160, height: 160)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(.brandHero)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Notifications")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Optional. We'll only notify you when storage is critically low — never for marketing or upsell.")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    requestNotifications()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: notificationsRequested ? "checkmark" : "bell")
                        Text(notificationsRequested ? "Permission Requested" : "Enable Notifications")
                    }
                    .font(.system(.body).weight(.semibold))
                    .frame(minWidth: 220)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
                .disabled(notificationsRequested)

                Text("You can change this anytime in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.08), .clear],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 600
            )
            RadialGradient(
                colors: [Color(nsColor: .systemTeal).opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func requestNotifications() {
        notificationsRequested = true
        Task {
            _ = try? await UNUserNotificationCenter
                .current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    private func complete() {
        onComplete()
    }
}

private struct FeatureBullet: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(text)
                .font(.system(.callout))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}
