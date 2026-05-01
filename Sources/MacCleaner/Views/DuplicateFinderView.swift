import SwiftUI
import UniformTypeIdentifiers

// MARK: - View Model

@MainActor
final class DuplicateFinderViewModel: ObservableObject {
    @Published var folders: [URL]
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var scanScanned: Int = 0
    @Published var scanTotal: Int = 0
    @Published var selectedURLs: Set<URL> = []
    @Published var minimumSize: Int64 = 1 * 1024 * 1024
    @Published var lastResult: ResultSummary?

    struct ResultSummary {
        let bytesFreed: Int64
        let count: Int
        let errors: [FileCleanupError]
    }

    /// Default folders most users want scanned. Computed once.
    static let defaultFolders: [URL] = {
        let home = NSHomeDirectory()
        return [
            URL(fileURLWithPath: home + "/Documents"),
            URL(fileURLWithPath: home + "/Downloads"),
            URL(fileURLWithPath: home + "/Desktop"),
            URL(fileURLWithPath: home + "/Pictures"),
            URL(fileURLWithPath: home + "/Movies"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }()

    static let thresholdOptions: [Int64] = [
        100 * 1024,
        1 * 1024 * 1024,
        10 * 1024 * 1024,
        50 * 1024 * 1024,
        100 * 1024 * 1024,
    ]

    private let finder = DuplicateFileFinder()
    private var scanTask: Task<Void, Never>?

    init() {
        self.folders = Self.defaultFolders
    }

    var totalWasted: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var selectedSize: Int64 {
        var total: Int64 = 0
        for group in groups {
            for file in group.files where selectedURLs.contains(file.url) {
                total += group.size
            }
        }
        return total
    }

    var selectedCount: Int { selectedURLs.count }

    func startScan() {
        guard !isScanning, !folders.isEmpty else { return }
        scanTask?.cancel()
        isScanning = true
        scanScanned = 0
        scanTotal = 0
        groups = []
        selectedURLs = []
        lastResult = nil

        let folders = self.folders
        let minimum = self.minimumSize
        scanTask = Task { [weak self] in
            guard let self else { return }
            let finder = self.finder
            let result = await finder.scan(
                folders: folders,
                minimumSize: minimum
            ) { @MainActor scanned, total in
                self.scanScanned = scanned
                self.scanTotal = total
            }
            self.groups = result
            self.isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func addFolders(_ urls: [URL]) {
        for url in urls where !folders.contains(url) {
            folders.append(url)
        }
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
    }

    /// Auto-select duplicates across all groups according to `strategy`. The
    /// chosen "winner" of each group is preserved; everything else is selected
    /// for deletion.
    func autoSelect(strategy: KeepStrategy) {
        var newSelection: Set<URL> = []
        for group in groups {
            for url in group.urlsToDelete(strategy: strategy) {
                newSelection.insert(url)
            }
        }
        selectedURLs = newSelection
    }

    /// Auto-select within a single group only.
    func autoSelectGroup(_ group: DuplicateGroup, strategy: KeepStrategy) {
        // Clear any existing selection from this group, then apply.
        for file in group.files {
            selectedURLs.remove(file.url)
        }
        for url in group.urlsToDelete(strategy: strategy) {
            selectedURLs.insert(url)
        }
    }

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Trash everything in `selectedURLs`. Always recoverable — duplicates are
    /// scary. After trashing, refresh `groups` to drop any group with < 2 copies
    /// remaining.
    func trashSelected() async {
        let urls = Array(selectedURLs)
        guard !urls.isEmpty else { return }

        let result = await finder.delete(urls)
        let trashedSet = Set(urls)

        var refreshed: [DuplicateGroup] = []
        for group in groups {
            let remaining = group.files.filter { !trashedSet.contains($0.url) }
            if remaining.count >= 2 {
                refreshed.append(DuplicateGroup(
                    hash: group.hash,
                    size: group.size,
                    files: remaining
                ))
            }
        }
        groups = refreshed.sorted { $0.wastedBytes > $1.wastedBytes }
        selectedURLs = []
        lastResult = ResultSummary(
            bytesFreed: result.bytesFreed,
            count: urls.count - result.errors.count,
            errors: result.errors
        )
    }
}

// MARK: - Main View

struct DuplicateFinderView: View {
    @StateObject private var viewModel = DuplicateFinderViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showFolderImporter = false
    @State private var showFolderManager = false
    @State private var showTrashConfirmation = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    contentArea
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, viewModel.selectedURLs.isEmpty ? Theme.Spacing.xxl : 110)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }

            if !viewModel.selectedURLs.isEmpty {
                bottomToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: viewModel.selectedURLs.isEmpty)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .navigationTitle("Find Duplicates")
        .navigationSubtitle(navigationSubtitle)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.addFolders(urls)
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showFolderManager) {
            FolderManagerSheet(viewModel: viewModel) {
                showFolderImporter = true
            } onDismiss: {
                showFolderManager = false
            }
        }
        .alert(
            "Move \(viewModel.selectedCount) file\(viewModel.selectedCount == 1 ? "" : "s") to Trash?",
            isPresented: $showTrashConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.trashSelected() }
            }
        } message: {
            Text("\(ByteFormatter.format(viewModel.selectedSize)) will be moved to Trash. At least one copy of each file will remain.")
        }
    }

    private var navigationSubtitle: String {
        if viewModel.isScanning {
            return scanProgressText
        }
        if viewModel.groups.isEmpty {
            return "Across \(viewModel.folders.count) folder\(viewModel.folders.count == 1 ? "" : "s")"
        }
        return "\(viewModel.groups.count) duplicate group\(viewModel.groups.count == 1 ? "" : "s") · \(ByteFormatter.format(viewModel.totalWasted)) wasted"
    }

    private var scanProgressText: String {
        if viewModel.scanTotal == 0 {
            return "Indexing \(viewModel.scanScanned) files…"
        }
        return "Hashing \(viewModel.scanScanned) of \(viewModel.scanTotal) candidates"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find Duplicates")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Identical files across your selected folders, by content (SHA-256)")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !viewModel.groups.isEmpty {
                    autoSelectMenu
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showFolderManager = true
                } label: {
                    Label("\(viewModel.folders.count) folder\(viewModel.folders.count == 1 ? "" : "s")", systemImage: "folder.fill")
                        .font(.system(.callout).weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                thresholdMenu
                Spacer()
            }

            heroNumber
        }
    }

    private var thresholdMenu: some View {
        Menu {
            ForEach(DuplicateFinderViewModel.thresholdOptions, id: \.self) { threshold in
                Button {
                    viewModel.minimumSize = threshold
                } label: {
                    HStack {
                        Text("Min \(ByteFormatter.format(threshold))")
                        if viewModel.minimumSize == threshold {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.caption)
                Text("Min \(ByteFormatter.format(viewModel.minimumSize))")
                    .font(.system(.callout).weight(.medium))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Minimum file size to consider")
    }

    private var autoSelectMenu: some View {
        Menu {
            Section("Auto-select duplicates") {
                ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                    Button {
                        viewModel.autoSelect(strategy: strategy)
                    } label: {
                        Label(strategy.rawValue, systemImage: strategy.symbol)
                    }
                }
            }
            Divider()
            Button {
                viewModel.selectedURLs = []
            } label: {
                Label("Clear selection", systemImage: "xmark.circle")
            }
        } label: {
            Label("Auto-select", systemImage: "wand.and.stars")
                .font(.system(.callout).weight(.medium))
        }
        .menuStyle(.borderedButton)
        .controlSize(.regular)
        .fixedSize()
        .help("Auto-select duplicates across all groups")
    }

    private var heroNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WASTED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                AnimatedByteText(
                    bytes: viewModel.totalWasted,
                    font: .system(size: 56, weight: .bold, design: .rounded),
                    foreground: AnyShapeStyle(.brandHero),
                    kerning: -1.0
                )
            }

            statDivider

            VStack(alignment: .leading, spacing: 4) {
                Text("GROUPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                Text("\(viewModel.groups.count)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
            VStack(alignment: .trailing, spacing: 8) {
                if viewModel.scanTotal > 0 {
                    ProgressView(
                        value: Double(viewModel.scanScanned),
                        total: Double(max(viewModel.scanTotal, 1))
                    )
                    .progressViewStyle(.linear)
                    .frame(width: 180)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("\(viewModel.scanScanned) files")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            Button {
                viewModel.startScan()
            } label: {
                Label(viewModel.groups.isEmpty ? "Start Scan" : "Rescan", systemImage: viewModel.groups.isEmpty ? "magnifyingglass" : "arrow.clockwise")
                    .font(.system(.callout).weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.folders.isEmpty)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isScanning && viewModel.groups.isEmpty {
            scanningCard
        } else if viewModel.groups.isEmpty {
            emptyState
        } else {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.groups) { group in
                    DuplicateGroupCard(
                        group: group,
                        selectedURLs: viewModel.selectedURLs,
                        onToggle: { url in
                            withAnimation(Theme.Motion.quick) {
                                viewModel.toggleSelection(url)
                            }
                        },
                        onShowInFinder: { url in viewModel.showInFinder(url) },
                        onAutoSelect: { strategy in
                            withAnimation(Theme.Motion.smooth) {
                                viewModel.autoSelectGroup(group, strategy: strategy)
                            }
                        }
                    )
                }
            }
        }
    }

    private var scanningCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 32))
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                .foregroundStyle(.secondary)
            Text("Looking for duplicates…")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(scanProgressText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if viewModel.scanTotal > 0 {
                ProgressView(
                    value: Double(viewModel.scanScanned),
                    total: Double(max(viewModel.scanTotal, 1))
                )
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "square.on.square")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(viewModel.lastResult == nil ? "No scan yet" : "No duplicates found")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(viewModel.lastResult == nil
                     ? "Pick folders, choose a minimum size, and start a scan to find files with identical content."
                     : "All files in your scanned folders are unique above \(ByteFormatter.format(viewModel.minimumSize)).")
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
            .disabled(viewModel.folders.isEmpty)
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
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
                viewModel.selectedURLs = []
            } label: {
                Label("Clear", systemImage: "xmark.circle")
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
}

// MARK: - Group Card

private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let selectedURLs: Set<URL>
    let onToggle: (URL) -> Void
    let onShowInFinder: (URL) -> Void
    let onAutoSelect: (KeepStrategy) -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            cardHeader

            VStack(spacing: 1) {
                ForEach(group.files) { file in
                    DuplicateFileRow(
                        file: file,
                        size: group.size,
                        isSelected: selectedURLs.contains(file.url),
                        onToggle: { onToggle(file.url) },
                        onShowInFinder: { onShowInFinder(file.url) }
                    )
                }
            }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            HStack {
                Menu {
                    ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                        Button {
                            onAutoSelect(strategy)
                        } label: {
                            Label(strategy.rawValue, systemImage: strategy.symbol)
                        }
                    }
                } label: {
                    Label("Auto-select duplicates", systemImage: "wand.and.stars")
                        .font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                Text("SHA-256: \(group.hash.prefix(12))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .cardBackground(radius: Theme.Radius.lg, material: .regularMaterial)
        .scaleEffect(hovered ? 1.005 : 1.0)
        .animation(Theme.Motion.quick, value: hovered)
        .liftOnHover(hovered)
        .onHover { hovered = $0 }
    }

    private var cardHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(group.files.count) copies of ")
                    .foregroundStyle(.secondary)
                + Text(group.representativeName)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)

                Text("Each copy is \(ByteFormatter.format(group.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(.callout))
            .lineLimit(1)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormatter.format(group.wastedBytes))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.brandHero)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("wasted")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Duplicate File Row

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let size: Int64
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowInFinder: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.secondary))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(.system(.callout).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let date = file.modifiedDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 90, alignment: .trailing)
            }

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
        .accessibilityLabel(file.url.lastPathComponent)
        .accessibilityValue(isSelected ? "Marked for deletion" : "Will be kept")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.red.opacity(0.10)
        } else if hovered {
            Color.primary.opacity(0.04)
        } else {
            Color.clear
        }
    }
}

// MARK: - Folder Manager Sheet

private struct FolderManagerSheet: View {
    @ObservedObject var viewModel: DuplicateFinderViewModel
    let onAddFolders: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Folders")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)

            Divider()

            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    if viewModel.folders.isEmpty {
                        Text("No folders selected. Add at least one folder to scan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, Theme.Spacing.xxl)
                    } else {
                        ForEach(viewModel.folders, id: \.self) { folder in
                            FolderManagerRow(folder: folder) {
                                viewModel.removeFolder(folder)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    onAddFolders()
                } label: {
                    Label("Add Folders…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
        }
        .frame(width: 520, height: 420)
    }
}

private struct FolderManagerRow: View {
    let folder: URL
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.lastPathComponent)
                    .font(.system(.callout).weight(.medium))
                Text(folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .opacity(hovered ? 1 : 0.5)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(hovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Theme.Motion.quick, value: hovered)
    }
}
