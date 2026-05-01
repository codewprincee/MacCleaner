import SwiftUI

struct CleanupSummaryView: View {
    let summary: CleanupSummary
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showErrorDetails = false
    @State private var celebrate = false
    @State private var expandedResults: Set<UUID> = []
    @State private var bounceTrigger = false

    var body: some View {
        ZStack {
            // Backdrop — material on top of subtle window background.
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            } else {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }

            // Confetti only on full success.
            if celebrate
                && summary.failureCount == 0
                && summary.totalBytesFreed > 0
                && !reduceMotion {
                ConfettiCanvas()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                resultsSection
                if totalErrors > 0 {
                    errorBanner
                }
                Divider().opacity(0.4)
                footer
            }
        }
        .frame(width: 540, height: 640)
        .sheet(isPresented: $showErrorDetails) {
            ErrorDetailsView(summary: summary)
        }
        .onAppear {
            // Auto-expand any failed/partial categories.
            expandedResults = Set(
                summary.results
                    .filter { !$0.errors.isEmpty }
                    .map(\.id)
            )
            withAnimation(.easeOut(duration: 0.4).delay(0.05)) {
                celebrate = true
                bounceTrigger.toggle()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(headerColor.opacity(0.16))
                    .frame(width: 92, height: 92)

                Circle()
                    .stroke(headerColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 110, height: 110)

                Image(systemName: headerIcon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(headerColor)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, options: .nonRepeating, value: bounceTrigger)
            }
            .padding(.top, Theme.Spacing.xl)

            VStack(spacing: 6) {
                Text(headerTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))

                if summary.totalBytesFreed > 0 {
                    AnimatedByteText(
                        bytes: summary.totalBytesFreed,
                        font: Theme.Typography.display,
                        foreground: AnyShapeStyle(.brandHero),
                        kerning: -0.8
                    )

                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(headerEmptyState)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let before = summary.diskBefore, let after = summary.diskAfter {
                DiskComparisonStrip(before: before, after: after)
                    .padding(.horizontal, Theme.Spacing.xl)
            } else if let after = summary.diskAfter {
                FreeSpaceStrip(disk: after)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(summary.results) { result in
                    ResultDisclosureRow(
                        result: result,
                        isExpanded: expandedResults.contains(result.id)
                    ) {
                        withAnimation(Theme.Motion.snappy) {
                            if expandedResults.contains(result.id) {
                                expandedResults.remove(result.id)
                            } else {
                                expandedResults.insert(result.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        Button {
            showErrorDetails = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(totalErrors) item\(totalErrors == 1 ? "" : "s") had errors")
                    .font(.system(.callout).weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.orange.opacity(0.08))
            .overlay(alignment: .leading) {
                Rectangle().fill(.orange).frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Show detailed error list")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                // Placeholder — wired to a future history view.
            } label: {
                Label("View History", systemImage: "clock.arrow.circlepath")
                    .font(.system(.callout).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Coming soon")
            .disabled(true)

            Button {
                // Placeholder — wired to a future scheduling sheet.
            } label: {
                Label("Schedule Weekly Clean", systemImage: "calendar.badge.clock")
                    .font(.system(.callout).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Coming soon")
            .disabled(true)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.system(.body).weight(.semibold))
                    .frame(minWidth: 90)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Computed

    private var headerIcon: String {
        if summary.failureCount == 0 { return "checkmark.seal.fill" }
        if summary.successCount > 0 { return "exclamationmark.triangle.fill" }
        return "xmark.octagon.fill"
    }

    private var headerColor: Color {
        if summary.failureCount == 0 { return .green }
        if summary.successCount > 0 { return .orange }
        return .red
    }

    private var headerTitle: String {
        if summary.totalBytesFreed == 0 && summary.failureCount > 0 { return "Cleanup Failed" }
        if summary.failureCount == 0 { return "All Clean" }
        return "Mostly Clean"
    }

    private var headerSubtitle: String {
        if summary.failureCount == 0 { return "freed up" }
        return "freed (some items skipped)"
    }

    private var headerEmptyState: String {
        if summary.failureCount > 0 { return "We couldn't free anything" }
        return "Nothing to free"
    }

    private var totalErrors: Int {
        summary.results.reduce(0) { $0 + $1.errors.count }
    }
}

// MARK: - Result Disclosure Row

private struct ResultDisclosureRow: View {
    let result: CleanupResult
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.type.rawValue)
                            .font(.system(.callout).weight(.semibold))
                            .foregroundStyle(.primary)
                        if !result.message.isEmpty {
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if result.success || result.partialSuccess {
                        Text(ByteFormatter.format(result.bytesFreed))
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("Failed")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    if !result.errors.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm + 2)
            }
            .buttonStyle(.plain)
            .disabled(result.errors.isEmpty)
            .contentShape(Rectangle())

            if isExpanded && !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.errors.prefix(5)) { error in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(error.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(error.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if result.errors.count > 5 {
                        Text("+ \(result.errors.count - 5) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm + 2)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        }
    }

    private var icon: String {
        if result.success { return "checkmark.circle.fill" }
        if result.partialSuccess { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private var color: Color {
        if result.success { return .green }
        if result.partialSuccess { return .orange }
        return .red
    }
}

// MARK: - Disk Comparison Strip

private struct DiskComparisonStrip: View {
    let before: DiskUsageInfo
    let after: DiskUsageInfo

    @State private var showAfter = false

    private var delta: Int64 { after.freeSpace - before.freeSpace }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            DiskMetric(
                label: "Before",
                value: ByteFormatter.format(before.freeSpace),
                accent: .secondary
            )
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            DiskMetric(
                label: "After",
                value: ByteFormatter.format(showAfter ? after.freeSpace : before.freeSpace),
                accent: .accentColor
            )
            Spacer()
            if delta > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                    Text("+\(ByteFormatter.format(delta))")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.12), in: Capsule())
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
        .onAppear {
            withAnimation(.smooth(duration: 0.8).delay(0.2)) { showAfter = true }
        }
    }
}

private struct DiskMetric: View {
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

private struct FreeSpaceStrip: View {
    let disk: DiskUsageInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            Text("\(ByteFormatter.format(disk.freeSpace)) free")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .monospacedDigit()
            Spacer()
            Text("of \(ByteFormatter.format(disk.totalSpace))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(.thinMaterial)
        }
    }
}

// MARK: - Confetti

private struct ConfettiCanvas: View {
    private struct Confetti {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var rot: CGFloat
        var rotSpeed: CGFloat
        var color: Color
        var size: CGFloat
        var birth: TimeInterval
    }

    @State private var pieces: [Confetti] = []
    @State private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .indigo, .pink, .accentColor]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let elapsed = CGFloat(now - startTime)

                if pieces.isEmpty {
                    DispatchQueue.main.async { spawn(now: now) }
                }

                for piece in pieces {
                    let age = CGFloat(now - piece.birth)
                    let x = piece.x + piece.vx * age * 60
                    let y = piece.y + piece.vy * age * 60 + 0.5 * 280 * age * age
                    let opacity = max(0, 1 - age / 3.5)
                    if opacity <= 0 { continue }

                    var transform = CGAffineTransform(translationX: x * size.width, y: y * size.height)
                    transform = transform.rotated(by: Double(piece.rot + piece.rotSpeed * elapsed))

                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    context.transform = transform
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(piece.color.opacity(opacity))
                    )
                    context.transform = .identity
                }
            }
        }
    }

    private func spawn(now: TimeInterval) {
        var newPieces: [Confetti] = []
        for _ in 0..<70 {
            newPieces.append(
                Confetti(
                    x: CGFloat.random(in: 0.2...0.8),
                    y: CGFloat.random(in: 0.05...0.2),
                    vx: CGFloat.random(in: -0.6...0.6),
                    vy: CGFloat.random(in: 0.2...0.8),
                    rot: CGFloat.random(in: 0...(.pi * 2)),
                    rotSpeed: CGFloat.random(in: -3...3),
                    color: palette.randomElement() ?? .blue,
                    size: CGFloat.random(in: 6...10),
                    birth: now
                )
            )
        }
        pieces = newPieces
    }
}

// MARK: - Error Details (kept lightweight)

struct ErrorDetailsView: View {
    let summary: CleanupSummary
    @Environment(\.dismiss) private var dismiss

    private var errorGroups: [(type: CleanupType, errors: [FileCleanupError])] {
        summary.results
            .filter { !$0.errors.isEmpty }
            .map { (type: $0.type, errors: $0.errors) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Cleanup Errors")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(errorGroups, id: \.type.id) { item in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Image(systemName: item.type.icon)
                                    .foregroundStyle(item.type.accentColor)
                                Text(item.type.rawValue)
                                    .font(.system(.callout).weight(.semibold))
                                Spacer()
                                Text("\(item.errors.count) error\(item.errors.count == 1 ? "" : "s")")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(item.errors) { error in
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red.opacity(0.7))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(error.path)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                        Text(error.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(Theme.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560, height: 460)
    }
}
