import SwiftUI

// MARK: - View Model

@MainActor
final class LargeFilesViewModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var isScanning = false
    @Published var scanProgress: Int = 0
    @Published var selectedKinds: Set<LargeFileKind> = Set(LargeFileKind.allCases)
    @Published var minimumSize: Int64 = 100 * 1024 * 1024
    @Published var selectedFiles: Set<UUID> = []
    @Published var lastResult: ResultSummary?

    /// Brief banner state — appears for 5s after a successful trash so the user can Undo.
    @Published var undoBanner: UndoBanner?

    /// Mapping from a deleted file's id -> the URL inside `~/.Trash` so Undo can
    /// restore it. Cleared 5s after the trash event.
    private var trashedItems: [(LargeFile, URL)] = []
    private var bannerDismissTask: Task<Void, Never>?

    struct ResultSummary {
        let bytesFreed: Int64
        let errors: [FileCleanupError]
    }

    struct UndoBanner: Identifiable {
        let id = UUID()
        let bytesFreed: Int64
        let count: Int
    }

    private let finder = LargeFileFinder()
    private var scanTask: Task<Void, Never>?

    /// Reasonable preset thresholds for the size picker.
    static let thresholdOptions: [Int64] = [
        50 * 1024 * 1024,
        100 * 1024 * 1024,
        250 * 1024 * 1024,
        500 * 1024 * 1024,
        1000 * 1024 * 1024,
    ]

    var filteredFiles: [LargeFile] {
        files.filter { selectedKinds.contains($0.kind) }
    }

    var totalSize: Int64 { filteredFiles.reduce(0) { $0 + $1.size } }

    var selectedSize: Int64 {
        filteredFiles
            .filter { selectedFiles.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        filteredFiles.filter { selectedFiles.contains($0.id) }.count
    }

    func startScan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        scanProgress = 0
        files = []
        selectedFiles = []
        lastResult = nil

        let threshold = minimumSize
        scanTask = Task { [weak self] in
            guard let self else { return }
            let finder = self.finder
            let results = await finder.scan(
                rootPath: NSHomeDirectory(),
                minimumSize: threshold
            ) { @MainActor count in
                self.scanProgress = count
            }
            self.files = results
            self.isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    func toggleKind(_ kind: LargeFileKind) {
        if selectedKinds.contains(kind) {
            selectedKinds.remove(kind)
        } else {
            selectedKinds.insert(kind)
        }
    }

    func toggleSelection(_ file: LargeFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    func selectAllVisible() {
        selectedFiles = Set(filteredFiles.map(\.id))
    }

    func deselectAll() {
        selectedFiles = []
    }

    func showInFinder(_ file: LargeFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func showSelectionInFinder() {
        let urls = filteredFiles.filter { selectedFiles.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Move all currently-selected files to Trash. After completion, expose an
    /// Undo banner for 5 seconds (the resulting URLs are remembered until then).
    func trashSelected() async {
        let toDelete = filteredFiles.filter { selectedFiles.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        // Trash one at a time so we can capture the resulting URL for Undo.
        var freed: Int64 = 0
        var errors: [FileCleanupError] = []
        var pairs: [(LargeFile, URL)] = []

        let fm = FileManager.default
        for file in toDelete {
            do {
                var resulting: NSURL?
                try fm.trashItem(at: file.url, resultingItemURL: &resulting)
                freed += file.size
                if let resultingURL = resulting as? URL {
                    pairs.append((file, resultingURL))
                }
            } catch {
                errors.append(FileCleanupError(
                    path: file.url.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        // Drop the trashed entries from the visible list.
        let trashedIds = Set(toDelete.map(\.id))
        files.removeAll { trashedIds.contains($0.id) }
        selectedFiles.subtract(trashedIds)
        lastResult = ResultSummary(bytesFreed: freed, errors: errors)

        if !pairs.isEmpty {
            trashedItems = pairs
            undoBanner = UndoBanner(bytesFreed: freed, count: pairs.count)
            bannerDismissTask?.cancel()
            bannerDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    self?.undoBanner = nil
                    self?.trashedItems = []
                }
            }
        }
    }

    /// Restore everything in the most recent trash batch. Each `resultingItemURL`
    /// is moved back to the file's original location.
    func undoLastTrash() {
        let fm = FileManager.default
        var restored: [LargeFile] = []
        for (original, trashed) in trashedItems {
            do {
                try fm.moveItem(at: trashed, to: original.url)
                restored.append(original)
            } catch {
                // Silent — the file may have been emptied from Trash by the user.
            }
        }
        files.append(contentsOf: restored)
        files.sort { $0.size > $1.size }
        trashedItems = []
        undoBanner = nil
        bannerDismissTask?.cancel()
    }
}

// MARK: - Main View

struct LargeFilesView: View {
    @StateObject private var viewModel = LargeFilesViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showTrashConfirmation = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    kindFilterRow
                    contentArea
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, viewModel.selectedFiles.isEmpty ? Theme.Spacing.xxl : 110)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }

            if !viewModel.selectedFiles.isEmpty {
                bottomToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let banner = viewModel.undoBanner {
                undoToast(banner)
                    .padding(.bottom, viewModel.selectedFiles.isEmpty ? Theme.Spacing.xl : 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: viewModel.selectedFiles.isEmpty)
        .animation(Theme.Motion.smooth, value: viewModel.undoBanner?.id)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .navigationTitle("Large Files")
        .navigationSubtitle(navigationSubtitle)
        .alert(
            "Move \(viewModel.selectedCount) file\(viewModel.selectedCount == 1 ? "" : "s") to Trash?",
            isPresented: $showTrashConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.trashSelected() }
            }
        } message: {
            Text("\(ByteFormatter.format(viewModel.selectedSize)) will be moved to Trash. You can restore items from Trash if needed.")
        }
    }

    private var navigationSubtitle: String {
        if viewModel.isScanning {
            return "Scanning your home folder…"
        }
        if viewModel.files.isEmpty {
            return "Find files over \(ByteFormatter.format(viewModel.minimumSize))"
        }
        return "\(viewModel.filteredFiles.count) file\(viewModel.filteredFiles.count == 1 ? "" : "s") · \(ByteFormatter.format(viewModel.totalSize))"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Large Files")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Files over the size threshold across your home folder")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                thresholdMenu
            }

            heroNumber
        }
    }

    private var thresholdMenu: some View {
        Menu {
            ForEach(LargeFilesViewModel.thresholdOptions, id: \.self) { threshold in
                Button {
                    viewModel.minimumSize = threshold
                } label: {
                    HStack {
                        Text("Over \(ByteFormatter.format(threshold))")
                        if viewModel.minimumSize == threshold {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                Text("Over \(ByteFormatter.format(viewModel.minimumSize))")
                    .font(.system(.callout).weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change minimum file size")
    }

    private var heroNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FOUND")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                AnimatedByteText(
                    bytes: viewModel.totalSize,
                    font: .system(size: 56, weight: .bold, design: .rounded),
                    foreground: AnyShapeStyle(.brandHero),
                    kerning: -1.0
                )
            }

            statDivider

            VStack(alignment: .leading, spacing: 4) {
                Text("FILES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                Text("\(viewModel.filteredFiles.count)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
            }

            Spacer()

            scanControls
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .cardBackground(
            radius: Theme.Radius.xl,
            material: .thinMaterial,
            solid: reduceTransparency
        )
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(width: 0.5, height: 56)
    }

    @ViewBuilder
    private var scanControls: some View {
        if viewModel.isScanning {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(viewModel.scanProgress) files checked")
                        .font(.system(.callout).weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button("Cancel") {
                    viewModel.cancelScan()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Button {
                viewModel.startScan()
            } label: {
                Label(viewModel.files.isEmpty ? "Start Scan" : "Rescan", systemImage: viewModel.files.isEmpty ? "magnifyingglass" : "arrow.clockwise")
                    .font(.system(.callout).weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - Kind Filter

    private var kindFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(LargeFileKind.allCases, id: \.self) { kind in
                    KindChip(
                        kind: kind,
                        count: viewModel.files.filter { $0.kind == kind }.count,
                        isOn: viewModel.selectedKinds.contains(kind)
                    ) {
                        withAnimation(Theme.Motion.smooth) {
                            viewModel.toggleKind(kind)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isScanning && viewModel.files.isEmpty {
            scanningCard
        } else if viewModel.files.isEmpty {
            emptyState
        } else if viewModel.filteredFiles.isEmpty {
            noMatchesCard
        } else {
            filesList
        }
    }

    private var scanningCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                .foregroundStyle(.secondary)
            Text("Scanning…")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("\(viewModel.scanProgress) files checked")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Find your big files")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Scan your home folder for files over \(ByteFormatter.format(viewModel.minimumSize)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                viewModel.startScan()
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .font(.system(.callout).weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    private var noMatchesCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text("No matches in current filter")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Found \(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") over \(ByteFormatter.format(viewModel.minimumSize)), but none match the selected types.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    private var filesList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Files")
                    .font(Theme.Typography.sectionTitle)
                Spacer()
                Button(viewModel.selectedFiles.isEmpty ? "Select All" : "Deselect All") {
                    if viewModel.selectedFiles.isEmpty {
                        viewModel.selectAllVisible()
                    } else {
                        viewModel.deselectAll()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            VStack(spacing: 1) {
                ForEach(Array(viewModel.filteredFiles.enumerated()), id: \.element.id) { _, file in
                    LargeFileRow(
                        file: file,
                        isSelected: viewModel.selectedFiles.contains(file.id),
                        onToggle: {
                            withAnimation(Theme.Motion.quick) {
                                viewModel.toggleSelection(file)
                            }
                        },
                        onShowInFinder: {
                            viewModel.showInFinder(file)
                        }
                    )
                }
            }
            .cardBackground(radius: Theme.Radius.lg, material: .regularMaterial)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedCount) file\(viewModel.selectedCount == 1 ? "" : "s") selected")
                    .font(.system(.callout).weight(.semibold))
                Text(ByteFormatter.format(viewModel.selectedSize))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.brandHero)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                viewModel.showSelectionInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(role: .destructive) {
                showTrashConfirmation = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
                    .font(.system(.callout).weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator.opacity(0.6))
                .frame(height: 0.5)
        }
    }

    // MARK: - Undo Toast

    private func undoToast(_ banner: LargeFilesViewModel.UndoBanner) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Moved \(banner.count) file\(banner.count == 1 ? "" : "s") to Trash")
                    .font(.system(.callout).weight(.semibold))
                Text(ByteFormatter.format(banner.bytesFreed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button("Undo") {
                viewModel.undoLastTrash()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

// MARK: - Kind Chip

private struct KindChip: View {
    let kind: LargeFileKind
    let count: Int
    let isOn: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.caption)
                    .foregroundStyle(isOn ? kind.accent : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(kind.rawValue)
                    .font(.system(.callout).weight(.medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(kind.accent.opacity(0.16)) : AnyShapeStyle(.quaternary.opacity(hovered ? 0.6 : 0.4)))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? kind.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            }
            .foregroundStyle(.primary)
            .scaleEffect(hovered ? 1.02 : 1.0)
            .animation(Theme.Motion.quick, value: hovered)
            .animation(Theme.Motion.smooth, value: isOn)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(kind.rawValue), \(count) files")
        .accessibilityValue(isOn ? "Included" : "Excluded")
    }
}

// MARK: - File Row

private struct LargeFileRow: View {
    let file: LargeFile
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowInFinder: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Selection toggle
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.brandHero) : AnyShapeStyle(Color.secondary))
                .contentTransition(.symbolEffect(.replace))

            // Kind icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(file.kind.accent.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: file.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(file.kind.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            // Filename + path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(.callout).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.displayDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Modified date
            if let relative = file.relativeModified {
                Text(relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 90, alignment: .trailing)
            }

            // Size
            Text(ByteFormatter.format(file.size))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 80, alignment: .trailing)

            // Show-in-Finder action
            Button {
                onShowInFinder()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .opacity(hovered ? 1 : 0.4)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { hovered = $0 }
        .animation(Theme.Motion.quick, value: hovered)
        .animation(Theme.Motion.smooth, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.displayName)
        .accessibilityValue("\(ByteFormatter.format(file.size)), \(file.kind.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.12)
        } else if hovered {
            Color.primary.opacity(0.04)
        } else {
            Color.clear
        }
    }
}
