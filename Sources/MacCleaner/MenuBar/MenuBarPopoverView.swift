import SwiftUI
import AppKit

/// 320x420 popover panel that lives off the menu bar status item. Reads from
/// the SHARED `CleanupViewModel` so numbers always match the main window.
struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController
    let onClose: () -> Void

    @EnvironmentObject private var viewModel: CleanupViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)

            Divider().opacity(0.4)

            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    diskUsageCard
                    reclaimableCard
                    quickActionsRow
                }
                .padding(Theme.Spacing.lg)
            }

            Divider().opacity(0.4)

            footer
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .frame(width: 320, height: 420)
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : Theme.Motion.snappy, value: controller.pressureLevel)
        .animation(reduceMotion ? nil : Theme.Motion.smooth, value: viewModel.totalReclaimable)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.brandHero)
                    .frame(width: 36, height: 36)
                    .shadow(color: .accentColor.opacity(0.35), radius: 6, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("MacCleaner")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(pressureSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            pressureDot
                .accessibilityLabel(pressureAccessibility)
        }
    }

    private var pressureDot: some View {
        Circle()
            .fill(pressureColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: pressureColor.opacity(0.55), radius: 3)
    }

    private var pressureSubtitle: String {
        switch controller.pressureLevel {
        case .healthy:  return "Disk healthy"
        case .low:      return "Running low"
        case .critical: return "Critically full"
        }
    }

    private var pressureAccessibility: String {
        "Disk pressure: \(pressureSubtitle)"
    }

    private var pressureColor: Color {
        switch controller.pressureLevel {
        case .healthy:  return .green
        case .low:      return .orange
        case .critical: return .red
        }
    }

    // MARK: - Disk usage card

    private var diskUsageCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(volumeName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Text(usagePercentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            DiskUsageBar(
                fraction: usageFraction,
                gradient: usageGradient
            )
            .frame(height: 8)

            Text(availabilityText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.Radius.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(volumeName) — \(availabilityText)")
    }

    private var volumeName: String {
        controller.diskUsage?.volumeName ?? viewModel.diskUsage?.volumeName ?? "Macintosh HD"
    }

    private var usageFraction: Double {
        let usage = controller.diskUsage ?? viewModel.diskUsage
        return usage?.usedPercentage ?? 0
    }

    private var usagePercentText: String {
        let pct = Int((usageFraction * 100).rounded())
        return "\(pct)% used"
    }

    private var availabilityText: String {
        let usage = controller.diskUsage ?? viewModel.diskUsage
        guard let usage else { return "Calculating…" }
        return "\(ByteFormatter.format(usage.availableSpace)) available of \(ByteFormatter.format(usage.totalSpace))"
    }

    private var usageGradient: LinearGradient {
        switch controller.pressureLevel {
        case .healthy:
            return LinearGradient(
                colors: [.blue, Color(nsColor: .systemTeal)],
                startPoint: .leading, endPoint: .trailing
            )
        case .low:
            return LinearGradient(
                colors: [.orange, Color(nsColor: .systemYellow)],
                startPoint: .leading, endPoint: .trailing
            )
        case .critical:
            return LinearGradient(
                colors: [.red, .pink],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    // MARK: - Reclaimable card

    private var reclaimableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("RECLAIMABLE")
                .font(Theme.Typography.eyebrow)
                .foregroundStyle(.secondary)
                .tracking(1.2)

            AnimatedByteText(
                bytes: viewModel.totalReclaimable,
                font: .system(size: 36, weight: .bold, design: .rounded),
                foreground: AnyShapeStyle(.brandHero)
            )

            Text(reclaimableSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Button(action: quickClean) {
                HStack(spacing: Theme.Spacing.sm) {
                    if viewModel.isCleaning {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(quickCleanLabel)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(.brandHero)
                )
                .shadow(color: .accentColor.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(quickCleanDisabled)
            .opacity(quickCleanDisabled ? 0.55 : 1)
            .accessibilityLabel("Quick Clean — frees \(ByteFormatter.format(viewModel.totalReclaimable))")
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.Radius.md)
    }

    private var reclaimableSubtitle: String {
        if viewModel.isScanning {
            return "Scanning…"
        }
        if viewModel.totalReclaimable == 0 {
            return "Nothing to free up right now"
        }
        return "\(ByteFormatter.format(viewModel.totalReclaimable)) ready to free"
    }

    private var quickCleanLabel: String {
        if viewModel.isCleaning { return "Cleaning…" }
        if viewModel.isScanning { return "Scanning…" }
        return "Quick Clean"
    }

    private var quickCleanDisabled: Bool {
        viewModel.isCleaning
            || viewModel.isScanning
            || !viewModel.hasSelectedCategories
            || viewModel.totalReclaimable == 0
    }

    private func quickClean() {
        viewModel.requestCleanSelected()
        // Bring the main window forward so the user can confirm the cleanup
        // sheet — running it in the popover would lose context the moment
        // the user clicks elsewhere.
        controller.openMainWindow()
        onClose()
    }

    // MARK: - Quick actions row

    private var quickActionsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            QuickActionButton(
                icon: "trash.fill",
                label: "Empty Trash",
                tint: .red,
                isBusy: viewModel.isCleaning
            ) {
                Task { _ = await controller.emptyTrash() }
            }

            QuickActionButton(
                icon: "network",
                label: "Flush DNS",
                tint: .blue,
                isBusy: viewModel.isCleaning
            ) {
                Task { _ = await controller.flushDNS() }
            }

            QuickActionButton(
                icon: "macwindow",
                label: "Open App",
                tint: .accentColor,
                isBusy: false
            ) {
                controller.openMainWindow()
                onClose()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastCleanedText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                controller.openSettings()
                onClose()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")
        }
    }

    private var lastCleanedText: String {
        guard let date = viewModel.lastCleanedAt else { return "Never cleaned" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last cleaned: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - Disk usage bar

private struct DiskUsageBar: View {
    let fraction: Double
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(fraction, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary.opacity(0.6))
                Capsule()
                    .fill(gradient)
                    .frame(width: proxy.size.width * clamped)
                    .animation(.smooth(duration: 0.4), value: clamped)
            }
        }
    }
}

// MARK: - Quick action button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(hovered ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
}
