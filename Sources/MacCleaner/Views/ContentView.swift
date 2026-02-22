import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CleanupViewModel()

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header area
                VStack(spacing: 0) {
                    // App title bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacCleaner")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Free up disk space on your Mac")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if viewModel.isScanning {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary.opacity(0.5))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Disk usage bar
                    DiskUsageBarView(diskUsage: viewModel.diskUsage)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                // Scrollable category list
                ScrollView {
                    CategoryListView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                // Bottom toolbar
                ToolbarView(viewModel: viewModel)
            }

            // Cleaning progress overlay
            if viewModel.isCleaning {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)

                CleanupProgressView(
                    progress: viewModel.cleaningProgress,
                    currentCategory: viewModel.currentCleaningCategory
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isCleaning)
        .sheet(isPresented: $viewModel.showSummary) {
            if let summary = viewModel.cleanupSummary {
                CleanupSummaryView(summary: summary) {
                    viewModel.showSummary = false
                }
            }
        }
        .task {
            await viewModel.scanAll()
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}
