import SwiftUI

struct CategoryRowView: View {
    @ObservedObject var category: CleanupCategory
    let onClean: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: $category.isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .disabled(!category.isAvailable)
                .accessibilityLabel("Select \(category.type.rawValue)")

            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(category.type.rawValue)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(category.isAvailable ? .primary : .secondary)

                    if category.type.requiresElevation {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help("Requires administrator password")
                    }
                }

                Text(category.isAvailable
                     ? category.type.description
                     : (category.unavailableReason ?? "Not available"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Spacing.md)

            trailingControls
        }
        .padding(.vertical, Theme.Spacing.sm + 2)
        .padding(.horizontal, Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(isHovered && category.isAvailable
                      ? Color.primary.opacity(0.04)
                      : Color.clear)
        }
        .opacity(category.isAvailable ? 1.0 : 0.55)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(category.type.rawValue)
        .accessibilityValue(
            category.isAvailable
                ? ByteFormatter.format(category.estimatedSize)
                : (category.unavailableReason ?? "Unavailable")
        )
    }

    // MARK: - Subviews

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(iconBackground)
                .frame(width: 38, height: 38)
            Image(systemName: category.type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating, isActive: category.isCleaning)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if category.isScanning {
            ProgressView()
                .controlSize(.small)
                .frame(width: 80, alignment: .trailing)
        } else if category.isCleaning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Cleaning…")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if category.isAvailable {
            HStack(spacing: Theme.Spacing.sm) {
                Text(ByteFormatter.format(category.estimatedSize))
                    .font(Theme.Typography.tabular)
                    .foregroundStyle(category.estimatedSize > 0 ? .primary : .quaternary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 78, alignment: .trailing)

                Button(action: onClean) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(category.estimatedSize > 0 || category.type == .dnsCache
                                         ? Color.red
                                         : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(category.estimatedSize == 0 && category.type != .dnsCache)
                .help("Clean \(category.type.rawValue)")
                .accessibilityLabel("Clean \(category.type.rawValue) now")
                .opacity(isHovered || category.estimatedSize > 0 ? 1 : 0)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(Theme.Motion.quick, value: isHovered)
            }
        } else {
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Colors

    private var iconBackground: Color {
        guard category.isAvailable else { return Color.secondary.opacity(0.12) }
        return category.type.accentColor.opacity(0.15)
    }

    private var iconColor: Color {
        guard category.isAvailable else { return .secondary }
        return category.type.accentColor
    }
}
