import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - View Model

@MainActor
final class AppUninstallerViewModel: ObservableObject {
    @Published var installedApps: [UninstallableApp] = []
    @Published var selectedApp: UninstallableApp?
    @Published var leftovers: [AppLeftoverFile] = []
    @Published var selectedLeftovers: Set<UUID> = []
    @Published var isLoadingApps = false
    @Published var isScanning = false
    @Published var isUninstalling = false
    @Published var searchQuery = ""
    @Published var lastResult: UninstallResult?
    @Published var pendingConfirmation = false
    @Published var dropError: String?

    private let service = AppUninstallerService()

    var filteredApps: [UninstallableApp] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return installedApps
        }
        let q = searchQuery.lowercased()
        return installedApps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    var totalLeftoversSize: Int64 {
        leftovers.reduce(0) { $0 + $1.size }
    }

    var selectedLeftoversSize: Int64 {
        leftovers
            .filter { selectedLeftovers.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var groupedLeftovers: [(category: LeftoverCategory, files: [AppLeftoverFile])] {
        let grouped = Dictionary(grouping: leftovers) { $0.category }
        return grouped
            .map { (category: $0.key, files: $0.value) }
            .sorted { $0.category.sortPriority < $1.category.sortPriority }
    }

    func loadApps() async {
        isLoadingApps = true
        let apps = await service.discoverInstalledApps()
        installedApps = apps
        isLoadingApps = false
    }

    func selectApp(_ app: UninstallableApp) async {
        selectedApp = app
        leftovers = []
        selectedLeftovers = []
        isScanning = true
        let found = await service.findLeftovers(for: app)
        // Only commit if user hasn't moved on to another app while we scanned.
        if selectedApp?.bundleID == app.bundleID {
            leftovers = found
            // Default: every leftover is checked.
            selectedLeftovers = Set(found.map(\.id))
            isScanning = false
        }
    }

    func clearSelection() {
        selectedApp = nil
        leftovers = []
        selectedLeftovers = []
        lastResult = nil
    }

    /// Resolve a dropped `.app` URL into a discoverable app and select it.
    /// If it isn't already in `installedApps`, prepend it.
    func handleDroppedApp(at url: URL) async {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension == "app" else {
            dropError = "That's not an app bundle."
            return
        }
        guard let bundle = Bundle(url: resolved) else {
            dropError = "Couldn't read that app's Info.plist."
            return
        }
        let bundleID = bundle.bundleIdentifier
            ?? resolved.deletingPathExtension().lastPathComponent
        if bundleID == "com.codewprince.MacCleaner" {
            dropError = "MacCleaner can't uninstall itself."
            return
        }
        if let existing = installedApps.first(where: { $0.bundleURL == resolved || $0.bundleID == bundleID }) {
            await selectApp(existing)
            return
        }
        // App lives outside our search roots — discover it on the fly.
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? resolved.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        let installedDate = (try? FileManager.default.attributesOfItem(atPath: resolved.path))?[.creationDate] as? Date
        let size = FileSystemScanner.computeSize(at: resolved.path)
        let icon = NSWorkspace.shared.icon(forFile: resolved.path)

        var app = UninstallableApp(
            id: bundleID,
            bundleID: bundleID,
            name: name,
            version: version,
            bundleURL: resolved,
            installedDate: installedDate,
            mainAppSize: size,
            icon: nil
        )
        app.icon = icon
        installedApps.insert(app, at: 0)
        await selectApp(app)
    }

    func requestUninstall() {
        guard selectedApp != nil, !selectedLeftovers.isEmpty else { return }
        pendingConfirmation = true
    }

    func confirmUninstall() async {
        pendingConfirmation = false
        guard let app = selectedApp else { return }
        let chosen = leftovers.filter { selectedLeftovers.contains($0.id) }
        guard !chosen.isEmpty else { return }

        isUninstalling = true
        let result = await service.uninstall(app, leftovers: chosen)
        lastResult = result

        // Drop the now-uninstalled app from the list (only if the bundle was deleted).
        if chosen.contains(where: { $0.category == .mainBundle }) && result.success {
            installedApps.removeAll { $0.bundleID == app.bundleID }
            selectedApp = nil
            leftovers = []
            selectedLeftovers = []
        } else {
            // Re-scan leftovers so the UI reflects what's still there.
            let remaining = await service.findLeftovers(for: app)
            leftovers = remaining
            selectedLeftovers = Set(remaining.map(\.id))
        }
        isUninstalling = false
    }

    // MARK: - Per-category selection helpers

    func categoryAllSelected(_ category: LeftoverCategory) -> Bool {
        let ids = leftovers.filter { $0.category == category }.map(\.id)
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { selectedLeftovers.contains($0) }
    }

    func toggleCategory(_ category: LeftoverCategory) {
        let ids = leftovers.filter { $0.category == category }.map(\.id)
        let allOn = ids.allSatisfy { selectedLeftovers.contains($0) }
        if allOn {
            for id in ids { selectedLeftovers.remove(id) }
        } else {
            for id in ids { selectedLeftovers.insert(id) }
        }
    }

    func toggleLeftover(_ file: AppLeftoverFile) {
        if selectedLeftovers.contains(file.id) {
            selectedLeftovers.remove(file.id)
        } else {
            selectedLeftovers.insert(file.id)
        }
    }
}

// MARK: - Main View

struct AppUninstallerView: View {
    @StateObject private var viewModel = AppUninstallerViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            detailPane
                .frame(minWidth: 540, idealWidth: 720)
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .navigationTitle("App Uninstaller")
        .navigationSubtitle(navigationSubtitle)
        .task {
            if viewModel.installedApps.isEmpty {
                await viewModel.loadApps()
            }
        }
        .sheet(isPresented: $viewModel.pendingConfirmation) {
            UninstallConfirmationSheet(
                app: viewModel.selectedApp,
                leftovers: viewModel.leftovers.filter { viewModel.selectedLeftovers.contains($0.id) },
                onConfirm: { Task { await viewModel.confirmUninstall() } },
                onCancel: { viewModel.pendingConfirmation = false }
            )
        }
        .sheet(item: Binding<UninstallResultBinding?>(
            get: { viewModel.lastResult.map(UninstallResultBinding.init) },
            set: { _ in viewModel.lastResult = nil }
        )) { binding in
            UninstallResultSheet(result: binding.result) {
                viewModel.lastResult = nil
            }
        }
    }

    private var navigationSubtitle: String {
        if viewModel.isLoadingApps { return "Discovering apps…" }
        let count = viewModel.installedApps.count
        return count > 0 ? "\(count) apps installed" : "No third-party apps found"
    }

    // MARK: - App list (left column)

    private var appList: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            Divider().opacity(0.4)

            if viewModel.isLoadingApps && viewModel.installedApps.isEmpty {
                loadingPlaceholder
            } else if viewModel.filteredApps.isEmpty {
                emptyAppList
            } else {
                List(viewModel.filteredApps, selection: Binding(
                    get: { viewModel.selectedApp?.bundleID },
                    set: { newID in
                        if let id = newID,
                           let app = viewModel.filteredApps.first(where: { $0.bundleID == id }) {
                            Task { await viewModel.selectApp(app) }
                        }
                    }
                )) { app in
                    AppListRow(app: app)
                        .tag(app.bundleID)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: Theme.Spacing.md) {
                    ShimmerPlaceholder(width: 32, height: 32, radius: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        ShimmerPlaceholder(width: 140, height: 12)
                        ShimmerPlaceholder(width: 80, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.md)
    }

    private var emptyAppList: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "app.dashed")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.searchQuery.isEmpty ? "No apps found" : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail pane (right column)

    private var detailPane: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if let app = viewModel.selectedApp {
                AppDetailContent(app: app, viewModel: viewModel)
            } else {
                emptyDetailState
            }

            // Drop overlay highlight.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .padding(Theme.Spacing.lg)
                    .overlay {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(.brandHero)
                            Text("Drop to scan")
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                            Text("Release to find every leftover file")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.snappy, value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.brandHero)
                    .frame(width: 88, height: 88)
                    .shadow(color: .accentColor.opacity(0.3), radius: 18, y: 6)
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("Uninstall any app, completely")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Pick an app on the left, or drop a .app onto this pane")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Spacing.lg) {
                FeatureBadge(icon: "magnifyingglass", title: "Deep scan",
                             subtitle: "15+ system locations")
                FeatureBadge(icon: "shield.lefthalf.filled", title: "Safe",
                             subtitle: "Bundle goes to Trash")
                FeatureBadge(icon: "lock.fill", title: "Privileged",
                             subtitle: "System paths supported")
            }
            .padding(.top, Theme.Spacing.md)

            if let error = viewModel.dropError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, Theme.Spacing.sm)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            viewModel.dropError = nil
                        }
                    }
            }
        }
        .padding(Theme.Spacing.xxl)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            Task { @MainActor in
                await viewModel.handleDroppedApp(at: url)
            }
        }
        return true
    }
}

// MARK: - App List Row

private struct AppListRow: View {
    let app: UninstallableApp

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            AppIconView(icon: app.icon, fallback: "app.fill", size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(.callout).weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let v = app.version, !v.isEmpty {
                        Text("v\(v)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(ByteFormatter.format(app.mainAppSize))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(ByteFormatter.format(app.mainAppSize))")
    }
}

// MARK: - App Icon

private struct AppIconView: View {
    let icon: NSImage?
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(.brandSubtle)
                    Image(systemName: fallback)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Detail content

private struct AppDetailContent: View {
    let app: UninstallableApp
    @ObservedObject var viewModel: AppUninstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    detailHeader
                    if viewModel.isScanning {
                        scanningHero
                    } else {
                        leftoversHero
                        leftoverGroups
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
            }

            if !viewModel.isScanning && !viewModel.leftovers.isEmpty {
                Divider().opacity(0.5)
                bottomBar
            }
        }
    }

    // MARK: Header

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            AppIconView(icon: app.icon, fallback: "app.fill", size: 64)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let version = app.version, !version.isEmpty {
                    Text("Version \(version)  ·  \(ByteFormatter.format(app.mainAppSize))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.requestUninstall()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Uninstall")
                }
                .font(.system(.body).weight(.semibold))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(viewModel.isScanning || viewModel.isUninstalling || viewModel.selectedLeftovers.isEmpty)
        }
    }

    // MARK: Hero

    private var scanningHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning every system location for leftovers…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: Theme.Spacing.md) {
                        ShimmerPlaceholder(width: 28, height: 28, radius: 7)
                        ShimmerPlaceholder(width: 220, height: 12)
                        Spacer()
                        ShimmerPlaceholder(width: 60, height: 12)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
        }
    }

    private var leftoversHero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECOVERABLE")
                    .font(Theme.Typography.eyebrow)
                    .foregroundStyle(.tertiary)
                AnimatedByteText(
                    bytes: viewModel.totalLeftoversSize,
                    font: Theme.Typography.heroCompact,
                    foreground: AnyShapeStyle(.brandHero)
                )
                Text("\(viewModel.leftovers.count) leftover items across \(viewModel.groupedLeftovers.count) categories")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.Radius.xl, material: .regularMaterial)
    }

    // MARK: Leftover groups

    private var leftoverGroups: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(viewModel.groupedLeftovers, id: \.category) { group in
                LeftoverCategorySection(
                    category: group.category,
                    files: group.files,
                    selectedIDs: $viewModel.selectedLeftovers,
                    isAllSelected: viewModel.categoryAllSelected(group.category),
                    onToggleAll: { viewModel.toggleCategory(group.category) },
                    onToggleFile: { viewModel.toggleLeftover($0) }
                )
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Text("\(viewModel.selectedLeftovers.count) of \(viewModel.leftovers.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(ByteFormatter.format(viewModel.selectedLeftoversSize))
                        .font(Theme.Typography.tabular)
                        .foregroundStyle(.brandHero)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            Button {
                viewModel.requestUninstall()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isUninstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(viewModel.isUninstalling ? "Uninstalling…" : "Uninstall & Clean")
                }
                .font(.system(.body).weight(.semibold))
                .frame(minWidth: 170)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .disabled(viewModel.selectedLeftovers.isEmpty || viewModel.isUninstalling)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(.bar)
    }
}

// MARK: - Category Section

private struct LeftoverCategorySection: View {
    let category: LeftoverCategory
    let files: [AppLeftoverFile]
    @Binding var selectedIDs: Set<UUID>
    let isAllSelected: Bool
    let onToggleAll: () -> Void
    let onToggleFile: (AppLeftoverFile) -> Void

    @State private var isExpanded: Bool = true

    private var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.4)
                fileList
            }
        }
        .cardBackground(radius: Theme.Radius.lg, material: .thinMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { isAllSelected },
                set: { _ in onToggleAll() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Toggle all \(category.rawValue)")

            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.brandHero)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)

            Text(category.rawValue)
                .font(.system(.callout).weight(.semibold))

            Text("\(files.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.5), in: Capsule())

            Spacer()

            Text(ByteFormatter.format(totalSize))
                .font(Theme.Typography.tabular)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                withAnimation(Theme.Motion.smooth) { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .contentShape(Rectangle())
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                LeftoverFileRow(
                    file: file,
                    isSelected: selectedIDs.contains(file.id),
                    onToggle: { onToggleFile(file) }
                )
                if idx < files.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
    }
}

// MARK: - File row

private struct LeftoverFileRow: View {
    let file: AppLeftoverFile
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(file.url.lastPathComponent)
                        .font(.system(.callout).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if file.isSystemPath {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help("Requires administrator privileges")
                    }
                }
                Text(displayPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormatter.format(file.size))
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isHovering ? AnyShapeStyle(.quaternary.opacity(0.3)) : AnyShapeStyle(Color.clear))
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
        }
    }

    /// Replace `$HOME` with `~` for compactness.
    private var displayPath: String {
        let home = NSHomeDirectory()
        if file.url.path.hasPrefix(home) {
            return "~" + file.url.path.dropFirst(home.count)
        }
        return file.url.path
    }
}

// MARK: - Feature Badge

private struct FeatureBadge: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.brandHero)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140)
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.sm)
        .cardBackground(radius: Theme.Radius.md, material: .thinMaterial)
    }
}

// MARK: - Confirmation Sheet

private struct UninstallConfirmationSheet: View {
    let app: UninstallableApp?
    let leftovers: [AppLeftoverFile]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var acknowledged = false

    private var totalSize: Int64 {
        leftovers.reduce(0) { $0 + $1.size }
    }

    private var hasSystemPaths: Bool {
        leftovers.contains(where: \.isSystemPath)
    }

    private var hasMainBundle: Bool {
        leftovers.contains(where: { $0.category == .mainBundle })
    }

    private var groupedSummary: [(category: LeftoverCategory, count: Int, size: Int64)] {
        let grouped = Dictionary(grouping: leftovers) { $0.category }
        return grouped
            .map { (category: $0.key, count: $0.value.count, size: $0.value.reduce(0) { $0 + $1.size }) }
            .sorted { $0.category.sortPriority < $1.category.sortPriority }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    warningBanner
                    summarySection
                }
                .padding(Theme.Spacing.xl)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 540, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            AppIconView(icon: app?.icon, fallback: "trash.fill", size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Uninstall \(app?.name ?? "App")?")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("\(leftovers.count) item\(leftovers.count == 1 ? "" : "s")  ·  \(ByteFormatter.format(totalSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("This cannot be fully undone")
                        .font(.system(.callout).weight(.semibold))
                    Text(warningText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Toggle(isOn: $acknowledged) {
                Text("I understand. Uninstall this app and remove the selected files.")
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

    private var warningText: String {
        var parts: [String] = []
        if hasMainBundle { parts.append("The app bundle moves to Trash (recoverable until emptied).") }
        parts.append("Caches, preferences, logs, and containers are deleted permanently.")
        if hasSystemPaths { parts.append("System paths require your administrator password.") }
        return parts.joined(separator: " ")
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WILL BE REMOVED")
                .font(Theme.Typography.eyebrow)
                .foregroundStyle(.tertiary)

            VStack(spacing: 0) {
                ForEach(Array(groupedSummary.enumerated()), id: \.element.category) { idx, item in
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: item.category.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.brandHero)
                                .symbolRenderingMode(.hierarchical)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.category.rawValue)
                                .font(.system(.callout).weight(.medium))
                            Text("\(item.count) item\(item.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(ByteFormatter.format(item.size))
                            .font(Theme.Typography.tabular)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    if idx < groupedSummary.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .cardBackground(radius: Theme.Radius.md, material: .thinMaterial)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(ByteFormatter.format(totalSize))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.brandHero)
                    .monospacedDigit()
            }
            Spacer()
            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            Button(role: .destructive) {
                onConfirm()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Uninstall")
                }
                .font(.system(.body).weight(.semibold))
                .frame(minWidth: 130)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            .disabled(!acknowledged)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }
}

// MARK: - Result Sheet

private struct UninstallResultSheet: View {
    let result: UninstallResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.brandHero)
                    .frame(width: 96, height: 96)
                    .shadow(color: .accentColor.opacity(0.45), radius: 24, y: 8)
                Image(systemName: result.success ? "checkmark" : "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text(result.success ? "Uninstalled cleanly" : "Mostly uninstalled")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text(result.app.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("FREED")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(ByteFormatter.format(result.bytesFreed))
                    .font(Theme.Typography.display)
                    .foregroundStyle(.brandHero)
                    .monospacedDigit()
                Text("\(result.filesRemoved) item\(result.filesRemoved == 1 ? "" : "s") removed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(result.errors.count) item\(result.errors.count == 1 ? "" : "s") could not be removed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(result.errors.prefix(3)) { err in
                        Text("· \(err.reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(radius: Theme.Radius.md, material: .thinMaterial)
                .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()

            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 140)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Identifiable wrapper for the result sheet

private struct UninstallResultBinding: Identifiable {
    let result: UninstallResult
    var id: UUID { result.id }
    init(result: UninstallResult) { self.result = result }
}
