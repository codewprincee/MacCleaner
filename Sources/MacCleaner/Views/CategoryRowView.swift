import SwiftUI

struct CategoryRowView: View {
    @ObservedObject var category: CleanupCategory
    let onClean: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle(isOn: $category.isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(!category.isAvailable)

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackground)
                    .frame(width: 34, height: 34)

                Image(systemName: category.type.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Name & description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(category.type.rawValue)
                        .font(.system(.body, weight: .medium))
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
            }

            Spacer()

            // Right side: size / progress / clean button
            if category.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60, alignment: .trailing)
            } else if category.isCleaning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cleaning...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if category.isAvailable {
                HStack(spacing: 8) {
                    Text(ByteFormatter.format(category.estimatedSize))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(category.estimatedSize > 0 ? .primary : .quaternary)
                        .frame(minWidth: 72, alignment: .trailing)

                    Button(action: onClean) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(category.estimatedSize > 0 ? .red : Color.gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(category.estimatedSize == 0 && category.type != .dnsCache)
                    .help("Clean \(category.type.rawValue)")
                    .opacity(isHovered || category.estimatedSize > 0 ? 1 : 0)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && category.isAvailable ? Color.primary.opacity(0.04) : .clear)
        }
        .opacity(category.isAvailable ? 1.0 : 0.5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var iconBackground: Color {
        guard category.isAvailable else { return .gray.opacity(0.1) }
        switch category.type {
        case .userCaches, .systemLogs, .tempFiles, .trash:
            return .blue.opacity(0.12)
        case .xcodeDerivedData, .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives:
            return .indigo.opacity(0.12)
        case .safariCache, .chromeCache:
            return .cyan.opacity(0.12)
        case .homebrewCache, .npmCache, .pipCache, .yarnCache, .cocoapodsCache:
            return .orange.opacity(0.12)
        case .systemCaches, .dnsCache:
            return .red.opacity(0.1)
        case .dockerData:
            return .teal.opacity(0.12)
        }
    }

    private var iconColor: Color {
        guard category.isAvailable else { return .gray }
        switch category.type {
        case .userCaches, .systemLogs, .tempFiles, .trash:
            return .blue
        case .xcodeDerivedData, .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives:
            return .indigo
        case .safariCache, .chromeCache:
            return .cyan
        case .homebrewCache, .npmCache, .pipCache, .yarnCache, .cocoapodsCache:
            return .orange
        case .systemCaches, .dnsCache:
            return .red
        case .dockerData:
            return .teal
        }
    }
}
