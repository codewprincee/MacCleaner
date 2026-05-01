import Foundation

/// Disk pressure level derived from the boot volume's used percentage.
///
/// Thresholds:
///   - `.healthy`  — usedPercentage <  0.75
///   - `.low`      — usedPercentage <  0.90
///   - `.critical` — usedPercentage >= 0.90
enum DiskPressureLevel: String, Sendable, Equatable {
    case healthy
    case low
    case critical

    init(usedPercentage: Double) {
        switch usedPercentage {
        case ..<0.75: self = .healthy
        case ..<0.90: self = .low
        default:      self = .critical
        }
    }

    /// SF Symbol that represents this pressure level in a menu bar status item.
    var sfSymbolName: String {
        switch self {
        case .healthy:  return "externaldrive"
        case .low:      return "externaldrive.badge.exclamationmark"
        case .critical: return "externaldrive.badge.xmark"
        }
    }
}

/// A `Sendable` snapshot of one polling cycle. We carry the disk usage so the
/// UI can show numbers without re-querying the filesystem on the main thread.
struct DiskPressureSnapshot: Sendable, Equatable {
    let level: DiskPressureLevel
    let usage: DiskUsageInfo?
    let polledAt: Date
}

/// Polls `DiskUsageInfo.current()` on a fixed cadence and exposes an
/// `AsyncStream<DiskPressureSnapshot>` consumers can iterate over.
///
/// The monitor is an `actor` so its mutable state (current task, continuations)
/// is safely confined. Multiple consumers can subscribe via `events()`.
actor DiskPressureMonitor {
    private var pollSeconds: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<DiskPressureSnapshot>.Continuation] = [:]
    private var lastSnapshot: DiskPressureSnapshot?

    init(pollSeconds: TimeInterval = 60) {
        self.pollSeconds = Self.clampInterval(pollSeconds)
    }

    /// Begin polling. Safe to call multiple times — only one polling task ever runs.
    func start() {
        guard pollTask == nil else { return }

        // Emit an immediate snapshot so subscribers don't have to wait `pollSeconds`
        // for their first value — the menu bar icon should be correct on launch.
        emitCurrent()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.currentPollSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.emitCurrent()
            }
        }
    }

    /// Stop polling and finish all open streams. Subscribers see their loops end.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    /// Update the polling cadence. Takes effect on the next iteration.
    func setPollSeconds(_ seconds: TimeInterval) {
        pollSeconds = Self.clampInterval(seconds)
    }

    /// Subscribe to pressure events. Each call returns a fresh stream; if a
    /// recent snapshot exists it is replayed immediately so consumers always
    /// see the current state.
    func events() -> AsyncStream<DiskPressureSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            if let last = lastSnapshot {
                continuation.yield(last)
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    /// Force an immediate poll without waiting for the next tick.
    func pollNow() {
        emitCurrent()
    }

    // MARK: - Private

    private var currentPollSeconds: TimeInterval { pollSeconds }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emitCurrent() {
        let usage = DiskUsageInfo.current()
        let level: DiskPressureLevel
        if let usage {
            level = DiskPressureLevel(usedPercentage: usage.usedPercentage)
        } else {
            // Failure mode: assume healthy rather than alarming the user with a
            // false-positive critical state when we couldn't read the volume.
            level = .healthy
        }
        let snapshot = DiskPressureSnapshot(level: level, usage: usage, polledAt: Date())
        lastSnapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private static func clampInterval(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, 30), 600)
    }
}
