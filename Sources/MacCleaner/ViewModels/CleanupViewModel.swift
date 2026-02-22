import Foundation
import SwiftUI

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published var categories: [CleanupCategory] = []
    @Published var diskUsage: DiskUsageInfo?
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var cleaningProgress: Double = 0
    @Published var currentCleaningCategory: String = ""
    @Published var showSummary = false
    @Published var cleanupSummary: CleanupSummary?

    private let cleanupService = CleanupService()

    var totalSelectedSize: Int64 {
        categories
            .filter { $0.isSelected && $0.isAvailable }
            .reduce(0) { $0 + $1.estimatedSize }
    }

    var hasSelectedCategories: Bool {
        categories.contains { $0.isSelected && $0.isAvailable }
    }

    var allSelected: Bool {
        categories.filter(\.isAvailable).allSatisfy(\.isSelected)
    }

    init() {
        categories = CleanupType.allCases.map { CleanupCategory(type: $0) }
    }

    // MARK: - Actions

    func scanAll() async {
        isScanning = true
        diskUsage = DiskUsageInfo.current()

        await withTaskGroup(of: Void.self) { group in
            for category in categories {
                group.addTask { [cleanupService] in
                    let type = category.type

                    await MainActor.run { category.isScanning = true }

                    let availability = await cleanupService.checkAvailability(for: type)
                    let size: Int64
                    if availability.available {
                        size = await cleanupService.estimateSize(for: type)
                    } else {
                        size = 0
                    }

                    await MainActor.run {
                        category.isAvailable = availability.available
                        category.unavailableReason = availability.reason
                        category.estimatedSize = size
                        category.isScanning = false
                        if !availability.available {
                            category.isSelected = false
                        }
                    }
                }
            }
        }

        isScanning = false
    }

    func cleanSelected() async {
        let selected = categories.filter { $0.isSelected && $0.isAvailable }
        guard !selected.isEmpty else { return }

        isCleaning = true
        cleaningProgress = 0

        let diskBefore = DiskUsageInfo.current()
        var results: [CleanupResult] = []

        for (index, category) in selected.enumerated() {
            currentCleaningCategory = category.type.rawValue
            category.isCleaning = true

            let result = await cleanupService.clean(category.type)
            results.append(result)

            category.isCleaning = false
            category.estimatedSize = max(category.estimatedSize - result.bytesFreed, 0)
            cleaningProgress = Double(index + 1) / Double(selected.count)
        }

        let diskAfter = DiskUsageInfo.current()
        diskUsage = diskAfter

        let totalFreed = results.reduce(Int64(0)) { $0 + $1.bytesFreed }
        cleanupSummary = CleanupSummary(
            results: results,
            totalBytesFreed: totalFreed,
            diskBefore: diskBefore,
            diskAfter: diskAfter
        )

        isCleaning = false
        showSummary = true
    }

    func cleanSingle(_ category: CleanupCategory) async {
        guard category.isAvailable else { return }

        category.isCleaning = true
        let result = await cleanupService.clean(category.type)
        category.isCleaning = false

        if result.success || result.partialSuccess {
            category.estimatedSize = max(category.estimatedSize - result.bytesFreed, 0)
        }

        diskUsage = DiskUsageInfo.current()

        cleanupSummary = CleanupSummary(
            results: [result],
            totalBytesFreed: result.bytesFreed,
            diskBefore: nil,
            diskAfter: diskUsage
        )
        showSummary = true
    }

    func toggleSelectAll() {
        let newValue = !allSelected
        for category in categories where category.isAvailable {
            category.isSelected = newValue
        }
    }
}
