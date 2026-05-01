import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: CleanupViewModel
    @State private var selection: SidebarSelection? = .smartClean
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $selection)
                    .environmentObject(viewModel)
                    .navigationSplitViewColumnWidth(
                        min: Theme.Window.sidebarMin,
                        ideal: Theme.Window.sidebarIdeal,
                        max: Theme.Window.sidebarMax
                    )
            } detail: {
                detailContent
                    .navigationSplitViewColumnWidth(min: 640, ideal: 880)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar { toolbarContent }

            // Cleaning overlay (animated, full-screen)
            if viewModel.isCleaning {
                CleanupProgressView(
                    progress: viewModel.cleaningProgress,
                    currentCategory: viewModel.currentCleaningCategory,
                    onCancel: { viewModel.cancelCleaning() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }
        }
        .animation(Theme.Motion.snappy, value: viewModel.isCleaning)
        .sheet(isPresented: $viewModel.showSummary) {
            if let summary = viewModel.cleanupSummary {
                CleanupSummaryView(summary: summary) {
                    viewModel.showSummary = false
                }
            }
        }
        .sheet(isPresented: $viewModel.pendingConfirmation) {
            CleanupConfirmationView(
                onConfirm: {
                    Task { await viewModel.confirmAndCleanSelected() }
                },
                onCancel: {
                    viewModel.pendingConfirmation = false
                }
            )
            .environmentObject(viewModel)
        }
        .task {
            if viewModel.diskUsage == nil {
                await viewModel.scanAll()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .smartClean {
        case .smartClean:
            SmartCleanView()
                .environmentObject(viewModel)
        case .appUninstaller:
            AppUninstallerView()
        case .largeFiles:
            LargeFilesView()
        case .duplicates:
            DuplicateFinderView()
        case .group(let group):
            CategoryDetailView(group: group)
                .environmentObject(viewModel)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(Theme.Motion.snappy) {
                    columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Toggle sidebar")
            .accessibilityLabel("Toggle sidebar")
        }

        ToolbarItem(placement: .principal) {
            ToolbarTitleView(viewModel: viewModel)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await viewModel.scanAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isScanning ? 360 : 0))
                    .animation(
                        viewModel.isScanning
                            ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isScanning
                    )
            }
            .disabled(viewModel.isScanning || viewModel.isCleaning)
            .help("Rescan (⌘R)")
            .accessibilityLabel("Rescan all categories")

            Button {
                viewModel.requestCleanSelected()
            } label: {
                Label("Clean", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(!viewModel.hasSelectedCategories || viewModel.isScanning || viewModel.isCleaning)
            .help("Clean selected (⌘K)")
            .accessibilityLabel("Clean selected categories")
        }
    }
}

/// Centered toolbar title. Shows "MacCleaner" with a small disk-pressure dot;
/// flips to a scanning pill while a scan is in progress.
private struct ToolbarTitleView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        if viewModel.isScanning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        } else {
            HStack(spacing: 8) {
                if let pct = viewModel.diskUsage?.usedPercentage {
                    Circle()
                        .fill(diskColor(pct))
                        .frame(width: 7, height: 7)
                        .help("Disk \(Int(pct * 100))% used")
                        .accessibilityHidden(true)
                }
                Text("MacCleaner")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func diskColor(_ pct: Double) -> Color {
        if pct > 0.9 { return .red }
        if pct > 0.75 { return .orange }
        return .green
    }
}
