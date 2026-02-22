import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CleanupViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Disk usage bar
                DiskUsageBarView(diskUsage: viewModel.diskUsage)
                    .padding()

                Divider()

                // Category list
                ScrollView {
                    CategoryListView(viewModel: viewModel)
                        .padding()
                }

                Divider()

                // Toolbar
                ToolbarView(viewModel: viewModel)
            }

            // Progress overlay
            if viewModel.isCleaning {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                CleanupProgressView(
                    progress: viewModel.cleaningProgress,
                    currentCategory: viewModel.currentCleaningCategory
                )
            }
        }
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
        .frame(minWidth: 600, minHeight: 500)
    }
}
