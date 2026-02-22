import SwiftUI

struct CategoryListView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            categorySection("File System", categories: fileSystemCategories)
            categorySection("Xcode", categories: xcodeCategories)
            categorySection("Browsers", categories: browserCategories)
            categorySection("Package Managers", categories: packageManagerCategories)
            categorySection("System (Requires Admin)", categories: systemCategories, isAdmin: true)
            categorySection("Containers", categories: dockerCategories, showBottomSpacer: false)
        }
    }

    private var fileSystemCategories: [CleanupCategory] {
        viewModel.categories.filter {
            [.userCaches, .systemLogs, .tempFiles, .trash].contains($0.type)
        }
    }

    private var xcodeCategories: [CleanupCategory] {
        viewModel.categories.filter {
            [.xcodeDerivedData, .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives].contains($0.type)
        }
    }

    private var browserCategories: [CleanupCategory] {
        viewModel.categories.filter {
            [.safariCache, .chromeCache].contains($0.type)
        }
    }

    private var packageManagerCategories: [CleanupCategory] {
        viewModel.categories.filter {
            [.homebrewCache, .npmCache, .pipCache, .yarnCache, .cocoapodsCache].contains($0.type)
        }
    }

    private var systemCategories: [CleanupCategory] {
        viewModel.categories.filter {
            [.systemCaches, .dnsCache].contains($0.type)
        }
    }

    private var dockerCategories: [CleanupCategory] {
        viewModel.categories.filter { $0.type == .dockerData }
    }

    @ViewBuilder
    private func categorySection(_ title: String, categories: [CleanupCategory],
                                 isAdmin: Bool = false, showBottomSpacer: Bool = true) -> some View {
        if !categories.isEmpty {
            Section {
                ForEach(categories) { category in
                    CategoryRowView(category: category) {
                        Task { await viewModel.cleanSingle(category) }
                    }
                    if category.id != categories.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            } header: {
                sectionHeader(title, isAdmin: isAdmin)
            }

            if showBottomSpacer {
                Spacer().frame(height: 16)
            }
        }
    }

    private func sectionHeader(_ title: String, isAdmin: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isAdmin {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}
