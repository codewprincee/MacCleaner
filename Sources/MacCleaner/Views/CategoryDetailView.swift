import SwiftUI

struct CategoryDetailView: View {
    let group: CategoryGroup
    @EnvironmentObject var viewModel: CleanupViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var categories: [CleanupCategory] {
        viewModel.categories(in: group)
    }

    private var availableCategories: [CleanupCategory] {
        categories.filter(\.isAvailable)
    }

    private var groupTotal: Int64 {
        viewModel.reclaimable(in: group)
    }

    private var groupSelectedSize: Int64 {
        categories.filter { $0.isSelected && $0.isAvailable }
            .reduce(0) { $0 + $1.estimatedSize }
    }

    private var allSelectedInGroup: Bool {
        let avail = availableCategories
        guard !avail.isEmpty else { return false }
        return avail.allSatisfy(\.isSelected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headerCard
                if !availableCategories.isEmpty {
                    categoriesSection
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .navigationTitle(group.rawValue)
        .navigationSubtitle(group.subtitle)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                        : AnyShapeStyle(.thinMaterial)
                )

            if !reduceTransparency {
                RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [group.accentColor.opacity(0.10), .clear],
                            center: .topTrailing,
                            startRadius: 40,
                            endRadius: 420
                        )
                    )
            }

            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(group.accentColor.opacity(0.16))
                        .frame(width: 76, height: 76)
                    Image(systemName: group.icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(group.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.rawValue)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        if group.requiresAdmin {
                            Label("Admin", systemImage: "lock.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 10).weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(group.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Theme.Spacing.lg) {
                        Statistic(
                            label: "Reclaimable",
                            value: ByteFormatter.format(groupTotal),
                            accent: .primary
                        )
                        Statistic(
                            label: "Selected",
                            value: ByteFormatter.format(groupSelectedSize),
                            accent: .secondary
                        )
                        Statistic(
                            label: "Items",
                            value: "\(availableCategories.count)",
                            accent: .secondary
                        )
                    }
                    .padding(.top, Theme.Spacing.sm)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task { await cleanGroup() }
                    } label: {
                        Label("Clean Group", systemImage: "sparkles")
                            .font(.system(.body).weight(.semibold))
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    .disabled(groupSelectedSize == 0 || viewModel.isCleaning || viewModel.isScanning)

                    Button {
                        toggleSelectAll()
                    } label: {
                        Text(allSelectedInGroup ? "Deselect All" : "Select All")
                            .font(.system(.callout).weight(.medium))
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(availableCategories.isEmpty || viewModel.isScanning || viewModel.isCleaning)
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Items")
                    .font(Theme.Typography.sectionTitle)
                Spacer()
                Text("\(availableCategories.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(availableCategories.enumerated()), id: \.element.id) { index, category in
                    CategoryRowView(category: category) {
                        Task { await viewModel.cleanSingle(category) }
                    }
                    if index < availableCategories.count - 1 {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
        }
    }

    /// Shown when none of the categories in this group apply to the user's system
    /// (e.g. they don't have any of the listed package managers / browsers installed).
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(group.accentColor.opacity(0.6))
                .symbolRenderingMode(.hierarchical)
            Text("Nothing to clean here")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("None of the apps or tools in this group are installed on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    // MARK: - Actions

    private func toggleSelectAll() {
        let target = !allSelectedInGroup
        for category in availableCategories {
            category.isSelected = target
        }
    }

    /// Selects everything currently selected in this group and routes through
    /// the confirmation sheet. Restores the user's prior selection state when
    /// the cleanup completes (or the user cancels).
    private func cleanGroup() async {
        // Snapshot prior selection so we can restore later.
        let previousSelection = viewModel.categories.map { ($0.id, $0.isSelected) }

        // Narrow selection to this group's available items, preserving the user's
        // existing toggle preferences within the group.
        for category in viewModel.categories {
            if category.type.group == group && category.isAvailable {
                let priorSelected = previousSelection.first(where: { $0.0 == category.id })?.1 ?? true
                category.isSelected = priorSelected
            } else {
                category.isSelected = false
            }
        }

        // Make sure at least one item is selected, otherwise fall back to all available.
        if !viewModel.categories.contains(where: { $0.isSelected && $0.isAvailable }) {
            for category in availableCategories { category.isSelected = true }
        }

        // Route through the confirmation flow. The actual cleanup happens after
        // the user confirms in the sheet.
        viewModel.requestCleanSelected()
    }
}

// MARK: - Statistic Block

private struct Statistic: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
