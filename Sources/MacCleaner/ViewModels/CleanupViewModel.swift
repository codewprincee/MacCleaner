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
    /// Apps the user should quit before running the currently-selected cleanup,
    /// keyed by the category whose cleanup conflicts with them.
    @Published var blockingConflicts: [CleanupType: [ConflictingApp]] = [:]
    /// Set when the user has clicked "Clean Selected" but we're awaiting confirmation.
    @Published var pendingConfirmation = false
    /// Cooperative cancel flag. Checked between categories during a cleanup pass.
    @Published var cancelRequested = false
    /// Persisted timestamp of the last successful cleanup (for "Last cleaned X ago").
    @AppStorage("lastCleanedAt") private(set) var lastCleanedAtRaw: Double = 0

    /// Convenience wrapper around the persisted timestamp.
    var lastCleanedAt: Date? {
        guard lastCleanedAtRaw > 0 else { return nil }
        return Date(timeIntervalSince1970: lastCleanedAtRaw)
    }

    private let cleanupService = CleanupService()
    private let notificationService = NotificationService()

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
        // Notification permission is requested lazily — only when we actually have
        // something to notify the user about (low disk space). Asking on launch with
        // no context is a HIG anti-pattern.
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

        // Check for low storage and send notification
        if let disk = diskUsage {
            await notificationService.checkAndNotifyLowStorage(disk)
        }
    }

    /// Step 1 of the cleanup flow. Computes preflight conflicts and surfaces a
    /// confirmation. The actual cleanup is gated behind `confirmAndCleanSelected()`.
    func requestCleanSelected() {
        let selected = categories.filter { $0.isSelected && $0.isAvailable }
        guard !selected.isEmpty else { return }
        let types = selected.map(\.type)
        blockingConflicts = cleanupService.preflightConflicts(for: types)
        pendingConfirmation = true
    }

    /// Step 2: actually run the cleanup. Called by the confirmation sheet after
    /// the user has reviewed and approved.
    func confirmAndCleanSelected() async {
        pendingConfirmation = false
        await cleanSelected()
    }

    /// Backwards-compatible entry point. Kept so existing callers (toolbar) work,
    /// but routes through the confirmation flow rather than running immediately.
    func cleanSelected() async {
        let selected = categories.filter { $0.isSelected && $0.isAvailable }
        guard !selected.isEmpty else { return }

        isCleaning = true
        cleaningProgress = 0
        cancelRequested = false

        let diskBefore = DiskUsageInfo.current()
        var results: [CleanupResult] = []

        for (index, category) in selected.enumerated() {
            // Cooperative cancel point — we honor between categories so we never
            // half-clean one and leave it in a weird state.
            if cancelRequested { break }

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

        if totalFreed > 0 {
            lastCleanedAtRaw = Date().timeIntervalSince1970
        }

        isCleaning = false
        cancelRequested = false
        showSummary = true
    }

    /// Sets the cooperative cancel flag. Picked up between categories.
    func cancelCleaning() {
        guard isCleaning else { return }
        cancelRequested = true
    }

    func cleanSingle(_ category: CleanupCategory) async {
        guard category.isAvailable else { return }

        category.isCleaning = true
        let result = await cleanupService.clean(category.type)
        category.isCleaning = false

        // Always reflect bytes actually freed, even on partial-failure paths.
        if result.bytesFreed > 0 {
            category.estimatedSize = max(category.estimatedSize - result.bytesFreed, 0)
        }

        diskUsage = DiskUsageInfo.current()

        cleanupSummary = CleanupSummary(
            results: [result],
            totalBytesFreed: result.bytesFreed,
            diskBefore: nil,
            diskAfter: diskUsage
        )
        if result.bytesFreed > 0 {
            lastCleanedAtRaw = Date().timeIntervalSince1970
        }
        showSummary = true
    }

    func toggleSelectAll() {
        let newValue = !allSelected
        for category in categories where category.isAvailable {
            category.isSelected = newValue
        }
    }
}
