import SwiftUI
import Charts

struct SmartCleanView: View {
    @EnvironmentObject var viewModel: CleanupViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var hoveredSegment: String?
    @Namespace private var heroNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroCard
                statStrip
                quickActionsSection
                breakdownSection
                lastCleanedFooter
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(detailBackground)
        .navigationTitle("Smart Clean")
        .navigationSubtitle(navigationSubtitle)
    }

    private var navigationSubtitle: String {
        if viewModel.isScanning { return "Scanning your Mac…" }
        let count = viewModel.reclaimableCategoryCount
        if count == 0 { return "Nothing to clean" }
        return "\(count) categor\(count == 1 ? "y" : "ies") with reclaimable space"
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack {
            // Subtle radial gradient backdrop — top-trailing accent at 8% -> clear.
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
                            colors: [
                                Color.accentColor.opacity(0.10),
                                Color(nsColor: .systemTeal).opacity(0.06),
                                .clear
                            ],
                            center: .topTrailing,
                            startRadius: 40,
                            endRadius: 460
                        )
                    )
            }

            // Center column.
            VStack(spacing: Theme.Spacing.lg) {
                // Eyebrow / scan badge.
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isScanning ? "sparkle" : "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(
                            .pulse,
                            options: reduceMotion ? .nonRepeating : .repeating,
                            isActive: viewModel.isScanning
                        )
                    Text(viewModel.isScanning ? "Smart Scan" : "Reclaimable Space")
                        .font(Theme.Typography.eyebrow)
                        .textCase(.uppercase)
                        .kerning(0.6)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: Capsule())

                // Hero number with donut surrounding it.
                ZStack {
                    HeroDonutChart(
                        segments: donutSegments,
                        total: viewModel.totalReclaimable,
                        isScanning: viewModel.isScanning,
                        reduceMotion: reduceMotion,
                        hoveredSegment: $hoveredSegment
                    )
                    .frame(width: 280, height: 280)

                    if viewModel.isScanning && viewModel.totalReclaimable == 0 {
                        ShimmerPlaceholder(width: 220, height: 64, radius: Theme.Radius.md)
                    } else {
                        AnimatedByteText(
                            bytes: viewModel.totalReclaimable,
                            font: .system(size: 56, weight: .bold, design: .rounded),
                            foreground: AnyShapeStyle(.brandHero),
                            kerning: -1.2
                        )
                        .matchedGeometryEffect(id: "heroNumber", in: heroNamespace)
                    }
                }
                .frame(height: 280)

                Text(heroSubtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Primary CTA.
                cleanButton
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var cleanButton: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                viewModel.requestCleanSelected()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                    Text("Clean \(ByteFormatter.format(viewModel.totalSelectedSize))")
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: 380)
                .frame(height: 56)
            }
            .buttonStyle(GlowingProminentButtonStyle())
            .disabled(!viewModel.hasSelectedCategories || viewModel.isScanning || viewModel.isCleaning)
            .accessibilityLabel("Clean selected categories, freeing \(ByteFormatter.format(viewModel.totalSelectedSize))")

            Button {
                viewModel.toggleSelectAll()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.allSelected ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.caption)
                    Text(viewModel.allSelected ? "Deselect All" : "Select All")
                }
                .font(.system(.callout).weight(.medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning || viewModel.isCleaning)
        }
    }

    private var heroSubtitle: String {
        if viewModel.isScanning && viewModel.totalReclaimable == 0 {
            return "Scanning your Mac for cruft…"
        }
        if viewModel.totalReclaimable == 0 {
            return "Your Mac is sparkling clean."
        }
        return "ready to free across \(activeGroupCount) categor\(activeGroupCount == 1 ? "y" : "ies")"
    }

    private var activeGroupCount: Int {
        CategoryGroup.allCases.filter { viewModel.reclaimable(in: $0) > 0 }.count
    }

    private var donutSegments: [DonutSegment] {
        CategoryGroup.allCases.compactMap { group in
            let bytes = viewModel.reclaimable(in: group)
            guard bytes > 0 else { return nil }
            return DonutSegment(
                id: group.rawValue,
                label: group.rawValue,
                bytes: bytes,
                color: group.accentColor
            )
        }
    }

    // MARK: - Stat Strip (categories scanned / files identified / largest)

    private var statStrip: some View {
        HStack(spacing: 0) {
            StatCell(
                label: "CATEGORIES",
                value: viewModel.isScanning && viewModel.totalReclaimable == 0
                    ? "—"
                    : "\(viewModel.reclaimableCategoryCount)",
                detail: "with reclaimable space"
            )
            statDivider
            StatCell(
                label: "TOTAL ITEMS",
                value: viewModel.isScanning && viewModel.totalReclaimable == 0
                    ? "—"
                    : "\(viewModel.categories.filter(\.isAvailable).count)",
                detail: "available to clean"
            )
            statDivider
            largestStatCell
        }
        .frame(height: 80)
        .cardBackground(
            radius: Theme.Radius.lg,
            material: .thinMaterial,
            solid: reduceTransparency
        )
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(width: 0.5, height: 44)
    }

    private var largestStatCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LARGEST ITEM")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)

            if let largest = viewModel.largestItem {
                Text(ByteFormatter.format(largest.estimatedSize))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(largest.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("nothing detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Quick Actions")
                .font(Theme.Typography.sectionTitle)

            HStack(spacing: Theme.Spacing.md) {
                QuickActionTile(
                    icon: "trash.fill",
                    title: "Empty Trash",
                    estimate: estimateFor(.trash),
                    accent: .accentColor
                ) {
                    if let trash = viewModel.categories.first(where: { $0.type == .trash }), trash.isAvailable {
                        Task { await viewModel.cleanSingle(trash) }
                    }
                }
                .disabled(viewModel.isCleaning || viewModel.isScanning)

                QuickActionTile(
                    icon: "network",
                    title: "Flush DNS",
                    estimate: estimateFor(.dnsCache),
                    accent: .accentColor
                ) {
                    if let dns = viewModel.categories.first(where: { $0.type == .dnsCache }), dns.isAvailable {
                        Task { await viewModel.cleanSingle(dns) }
                    }
                }
                .disabled(viewModel.isCleaning || viewModel.isScanning)

                QuickActionTile(
                    icon: "globe",
                    title: "Browser Caches",
                    estimate: ByteFormatter.format(
                        estimateBytesFor([.safariCache, .chromeCache])
                    ),
                    accent: .accentColor
                ) {
                    selectAndClean([.safariCache, .chromeCache])
                }
                .disabled(viewModel.isCleaning || viewModel.isScanning)

                QuickActionTile(
                    icon: "hammer.fill",
                    title: "Clean Xcode",
                    estimate: ByteFormatter.format(viewModel.reclaimable(in: .xcode)),
                    accent: .accentColor
                ) {
                    selectAndClean(CategoryGroup.xcode.types)
                }
                .disabled(viewModel.isCleaning || viewModel.isScanning)
            }
        }
    }

    private func estimateFor(_ type: CleanupType) -> String {
        guard let cat = viewModel.categories.first(where: { $0.type == type }) else { return "—" }
        return cat.isAvailable ? ByteFormatter.format(cat.estimatedSize) : "Unavailable"
    }

    private func estimateBytesFor(_ types: [CleanupType]) -> Int64 {
        viewModel.categories
            .filter { types.contains($0.type) && $0.isAvailable }
            .reduce(0) { $0 + $1.estimatedSize }
    }

    private func selectAndClean(_ types: [CleanupType]) {
        for category in viewModel.categories {
            category.isSelected = types.contains(category.type) && category.isAvailable
        }
        viewModel.requestCleanSelected()
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 6) {
                Text("Breakdown by Category")
                    .font(Theme.Typography.sectionTitle)
                Spacer()
                if viewModel.totalReclaimable > 0 {
                    Text("\(donutSegments.count) groups")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if viewModel.isScanning && viewModel.totalReclaimable == 0 {
                ScanningCard()
            } else if viewModel.totalReclaimable == 0 {
                EmptyStateCard(onRescan: { Task { await viewModel.scanAll() } })
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 240), spacing: Theme.Spacing.md)
                    ],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(CategoryGroup.allCases) { group in
                        let bytes = viewModel.reclaimable(in: group)
                        if bytes > 0 {
                            GroupSummaryCard(
                                group: group,
                                bytes: bytes,
                                percent: viewModel.totalReclaimable > 0
                                    ? Double(bytes) / Double(viewModel.totalReclaimable)
                                    : 0,
                                isHighlighted: hoveredSegment == group.rawValue,
                                onHoverChange: { hovering in
                                    withAnimation(Theme.Motion.smooth) {
                                        hoveredSegment = hovering ? group.rawValue : nil
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Last cleaned footer

    @ViewBuilder
    private var lastCleanedFooter: some View {
        if let date = viewModel.lastCleanedAt {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Last cleaned \(date.relative)")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var detailBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

// MARK: - Stat Cell

private struct StatCell: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

// MARK: - Hero Donut Chart (with hover)

struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let bytes: Int64
    let color: Color
}

private struct HeroDonutChart: View {
    let segments: [DonutSegment]
    let total: Int64
    let isScanning: Bool
    let reduceMotion: Bool
    @Binding var hoveredSegment: String?

    @State private var didAppear = false

    var body: some View {
        ZStack {
            if segments.isEmpty {
                // Soft pulsing ring while scanning, never just a spinner.
                Circle()
                    .strokeBorder(.quaternary.opacity(0.6), lineWidth: 18)
                    .padding(8)
                    .opacity(reduceMotion ? 1.0 : (didAppear ? 1.0 : 0.5))
                    .animation(
                        reduceMotion ? .default : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: didAppear
                    )
            } else {
                Chart(segments) { segment in
                    SectorMark(
                        angle: .value("Bytes", segment.bytes),
                        innerRadius: .ratio(0.72),
                        angularInset: 2
                    )
                    .cornerRadius(6)
                    .foregroundStyle(segment.color.gradient)
                    .opacity(hoveredSegment == nil || hoveredSegment == segment.id ? 1.0 : 0.35)
                }
                .chartLegend(.hidden)
                .chartBackground { _ in Color.clear }
                .opacity(didAppear ? 1 : 0)
                .scaleEffect(didAppear ? 1 : 0.9)
                .animation(reduceMotion ? .default : .easeOut(duration: 0.6), value: didAppear)
            }
        }
        .onAppear { didAppear = true }
        .onChange(of: total) { _, _ in
            // Re-trigger the bloom on rescan.
            withAnimation(.linear(duration: 0)) { didAppear = false }
            withAnimation(reduceMotion ? .default : .easeOut(duration: 0.6)) { didAppear = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reclaimable space breakdown")
        .accessibilityValue("Total \(ByteFormatter.format(total))")
    }
}

// MARK: - Group Summary Card

private struct GroupSummaryCard: View {
    let group: CategoryGroup
    let bytes: Int64
    let percent: Double
    let isHighlighted: Bool
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(group.accentColor.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: group.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(group.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.rawValue)
                        .font(.system(.callout).weight(.semibold))
                    Text(group.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(ByteFormatter.format(bytes))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text(String(format: "%.0f%%", percent * 100))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5))
                    Capsule()
                        .fill(group.accentColor.gradient)
                        .frame(width: geo.size.width * percent)
                        .animation(Theme.Motion.smooth, value: percent)
                }
            }
            .frame(height: 6)
        }
        .padding(Theme.Spacing.lg)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(group.accentColor.opacity(isHighlighted ? 0.55 : 0), lineWidth: 1)
        }
        .scaleEffect(hovered ? 1.01 : 1.0)
        .animation(Theme.Motion.quick, value: hovered)
        .liftOnHover(hovered)
        .onHover { hovering in
            hovered = hovering
            onHoverChange(hovering)
        }
    }
}

// MARK: - Quick Action Tile (120 x 120)

private struct QuickActionTile: View {
    let icon: String
    let title: String
    let estimate: String
    let accent: Color
    let action: () -> Void

    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.callout).weight(.semibold))
                    Text(estimate)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(Theme.Spacing.lg)
            .cardBackground(radius: Theme.Radius.md, material: .thinMaterial)
            .scaleEffect(pressed ? 0.97 : (hovered ? 1.015 : 1.0))
            .animation(Theme.Motion.quick, value: hovered)
            .animation(Theme.Motion.press, value: pressed)
            .liftOnHover(hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel("\(title), \(estimate)")
    }
}

// MARK: - Empty + Scanning States

private struct EmptyStateCard: View {
    let onRescan: () -> Void
    @State private var bounce = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
                .onAppear { bounce.toggle() }

            VStack(spacing: 4) {
                Text("All Clean")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Nothing to clean right now. Run another scan if you've used your Mac for a while.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onRescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(.system(.callout).weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }
}

private struct ScanningCard: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning categories…")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }
}

// MARK: - Glowing Prominent Button Style

struct GlowingProminentButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(.brandHero)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(
                color: isEnabled
                    ? Color.accentColor.opacity(configuration.isPressed ? 0.25 : (hovered ? 0.55 : 0.40))
                    : .clear,
                radius: configuration.isPressed ? 4 : (hovered ? 22 : 14),
                y: configuration.isPressed ? 1 : (hovered ? 10 : 6)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.55)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .animation(Theme.Motion.quick, value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Date helpers

private extension Date {
    /// "5 minutes ago" / "yesterday" — uses RelativeDateTimeFormatter.
    var relative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
