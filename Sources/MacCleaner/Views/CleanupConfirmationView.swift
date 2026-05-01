import SwiftUI

/// Modal confirmation shown before any selected-cleanup runs. Lists what will
/// be cleaned, surfaces conflicting apps that should be quit first, and gates
/// the destructive action on an explicit acknowledgement.
struct CleanupConfirmationView: View {
    @EnvironmentObject var viewModel: CleanupViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var acknowledgedConflicts = false

    private var selected: [CleanupCategory] {
        viewModel.categories.filter { $0.isSelected && $0.isAvailable }
    }

    private var totalBytes: Int64 {
        selected.reduce(0) { $0 + $1.estimatedSize }
    }

    private var hasConflicts: Bool {
        !viewModel.blockingConflicts.isEmpty
    }

    private var canConfirm: Bool {
        !selected.isEmpty && (!hasConflicts || acknowledgedConflicts)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if hasConflicts {
                        conflictBanner
                    }
                    categoriesList
                }
                .padding(Theme.Spacing.xl)
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 520, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.brandHero)
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean \(selected.count) categor\(selected.count == 1 ? "y" : "ies")?")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("This will permanently remove the items below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Conflict banner

    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Quit these apps first")
                        .font(.system(.callout).weight(.semibold))
                    Text("Cleaning their caches while running can corrupt their data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Deduplicate apps across cleanup types.
            let apps: [ConflictingApp] = {
                let set = Set(viewModel.blockingConflicts.values.flatMap { $0 })
                return set.sorted { $0.displayName < $1.displayName }
            }()

            FlowLayout(spacing: 6) {
                ForEach(apps, id: \.id) { app in
                    HStack(spacing: 5) {
                        Image(systemName: "app.dashed")
                            .font(.caption2)
                        Text(app.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
                }
            }

            Toggle(isOn: $acknowledgedConflicts) {
                Text("I understand these apps are running and want to clean anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
        .padding(Theme.Spacing.lg)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.75)
        }
    }

    // MARK: - Categories list

    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("WILL BE CLEANED")
                    .font(Theme.Typography.eyebrow)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(selected.count) item\(selected.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(selected.enumerated()), id: \.element.id) { index, cat in
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(cat.type.accentColor.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: cat.type.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(cat.type.accentColor)
                                .symbolRenderingMode(.hierarchical)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cat.type.rawValue)
                                .font(.system(.callout).weight(.medium))
                            Text(cat.type.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFormatter.format(cat.estimatedSize))
                            .font(Theme.Typography.tabular)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    if index < selected.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .cardBackground(radius: Theme.Radius.md, material: .thinMaterial)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(ByteFormatter.format(totalBytes))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.brandHero)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

            Button {
                onConfirm()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Clean Now")
                }
                .font(.system(.body).weight(.semibold))
                .frame(minWidth: 130)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }
}

// MARK: - Flow Layout (wraps tags onto new lines)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? lineWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
