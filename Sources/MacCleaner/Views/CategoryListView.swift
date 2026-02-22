import SwiftUI

struct CategoryListView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            categorySection("File System", icon: "folder.fill", categories: fileSystemCategories)
            categorySection("Xcode", icon: "hammer.fill", categories: xcodeCategories)
            categorySection("Browsers", icon: "globe", categories: browserCategories)
            categorySection("Package Managers", icon: "shippingbox.fill", categories: packageManagerCategories)
            categorySection("System", icon: "lock.shield.fill", categories: systemCategories, isAdmin: true)
            categorySection("Containers", icon: "cube.box.fill", categories: dockerCategories)
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
    private func categorySection(_ title: String, icon: String, categories: [CleanupCategory],
                                 isAdmin: Bool = false) -> some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // Section header
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if isAdmin {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    // Section total size
                    let sectionTotal = categories.reduce(Int64(0)) { $0 + $1.estimatedSize }
                    if sectionTotal > 0 {
                        Spacer()
                        Text(ByteFormatter.format(sectionTotal))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                // Category rows inside a card
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        CategoryRowView(category: category) {
                            Task { await viewModel.cleanSingle(category) }
                        }

                        if index < categories.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            }
        }
    }
}
