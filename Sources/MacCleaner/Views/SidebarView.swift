import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: CleanupViewModel
    @Binding var selection: SidebarSelection?

    /// Groups whose detail page would have at least one applicable category for this Mac.
    /// While the initial scan is in flight every category reports `isAvailable = true`
    /// (the default), so all groups stay visible until we have a real signal. After the
    /// scan, groups with zero installed apps/tools are hidden entirely.
    private var visibleGroups: [CategoryGroup] {
        // Don't filter while we're still discovering what's installed.
        if viewModel.isScanning && viewModel.totalReclaimable == 0 {
            return CategoryGroup.allCases
        }
        return CategoryGroup.allCases.filter { group in
            viewModel.categories(in: group).contains(where: \.isAvailable)
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                SmartCleanRow(
                    reclaimable: viewModel.totalReclaimable,
                    isScanning: viewModel.isScanning,
                    isSelected: selection == .smartClean
                )
                .tag(SidebarSelection.smartClean)
                .listRowSeparator(.hidden)

                AppUninstallerSidebarRow(
                    isSelected: selection == .appUninstaller
                )
                .tag(SidebarSelection.appUninstaller)
                .listRowSeparator(.hidden)

                LargeFilesSidebarRow(
                    isSelected: selection == .largeFiles
                )
                .tag(SidebarSelection.largeFiles)
                .listRowSeparator(.hidden)

                DuplicatesSidebarRow(
                    isSelected: selection == .duplicates
                )
                .tag(SidebarSelection.duplicates)
                .listRowSeparator(.hidden)
            }

            Section("Categories") {
                ForEach(visibleGroups) { group in
                    SidebarGroupRow(
                        group: group,
                        reclaimable: viewModel.reclaimable(in: group),
                        isScanning: viewModel.isScanning && viewModel.reclaimable(in: group) == 0
                    )
                    .tag(SidebarSelection.group(group))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DiskFooterView(diskUsage: viewModel.diskUsage)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
        }
    }
}

// MARK: - Smart Clean Row

private struct SmartCleanRow: View {
    let reclaimable: Int64
    let isScanning: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.brandHero)
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Smart Clean")
                    .font(.system(.body).weight(.semibold))
                Group {
                    if isScanning && reclaimable == 0 {
                        Text("Scanning…")
                    } else if reclaimable > 0 {
                        Text("\(ByteFormatter.format(reclaimable)) ready")
                    } else {
                        Text("All clean")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smart Clean")
        .accessibilityValue(reclaimable > 0 ? "\(ByteFormatter.format(reclaimable)) ready" : "All clean")
    }
}

// MARK: - App Uninstaller Row

private struct AppUninstallerSidebarRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.red.opacity(0.95), Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.red.opacity(0.30), radius: 6, y: 2)
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("App Uninstaller")
                    .font(.system(.body).weight(.semibold))
                Text("Remove apps & all leftovers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App Uninstaller")
        .accessibilityValue("Remove apps and all their leftover files")
    }
}

// MARK: - Large Files Row

private struct LargeFilesSidebarRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.purple.opacity(0.95), Color.pink.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.purple.opacity(0.30), radius: 6, y: 2)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Large Files")
                    .font(.system(.body).weight(.semibold))
                Text("Find files over 100 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Large Files")
        .accessibilityValue("Find files over 100 megabytes")
    }
}

// MARK: - Duplicates Row

private struct DuplicatesSidebarRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.teal.opacity(0.95), Color.blue.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.teal.opacity(0.30), radius: 6, y: 2)
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Duplicates")
                    .font(.system(.body).weight(.semibold))
                Text("Find identical files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Duplicates")
        .accessibilityValue("Find files with identical content")
    }
}

// MARK: - Group Row (Finder-density, 6pt vertical padding)

private struct SidebarGroupRow: View {
    let group: CategoryGroup
    let reclaimable: Int64
    let isScanning: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            Image(systemName: group.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(group.accentColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22)

            Text(group.rawValue)
                .font(.system(.callout).weight(.medium))
                .lineLimit(1)

            if group.requiresAdmin {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            if isScanning {
                ProgressView().controlSize(.small)
            } else if reclaimable > 0 {
                Text(ByteFormatter.format(reclaimable))
                    .font(.system(.callout, design: .rounded).weight(.regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.rawValue)
        .accessibilityValue(reclaimable > 0 ? ByteFormatter.format(reclaimable) : "Empty")
    }
}

// MARK: - Disk Footer

private struct DiskFooterView: View {
    let diskUsage: DiskUsageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(diskUsage?.volumeName ?? "Macintosh HD")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let pct = diskUsage?.usedPercentage {
                    Text("\(Int(pct * 100))%")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if let disk = diskUsage {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary.opacity(0.6))
                        Capsule()
                            .fill(barFill(disk.usedPercentage))
                            .frame(width: geo.size.width * min(disk.usedPercentage, 1.0))
                            .animation(Theme.Motion.smooth, value: disk.usedPercentage)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 4) {
                    Text("\(ByteFormatter.format(disk.freeSpace)) available")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("of \(ByteFormatter.format(disk.totalSpace))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Reading disk…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityFooterLabel)
    }

    private func barFill(_ pct: Double) -> AnyShapeStyle {
        if pct > 0.9 { return AnyShapeStyle(LinearGradient(colors: [.red, .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)) }
        if pct > 0.75 { return AnyShapeStyle(LinearGradient(colors: [.orange, .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)) }
        return AnyShapeStyle(LinearGradient.brandSubtle)
    }

    private var accessibilityFooterLabel: String {
        guard let disk = diskUsage else { return "Reading disk usage" }
        return "\(disk.volumeName), \(ByteFormatter.format(disk.freeSpace)) available of \(ByteFormatter.format(disk.totalSpace))"
    }
}
