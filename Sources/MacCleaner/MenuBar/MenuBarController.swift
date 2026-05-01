import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Owns the `NSStatusItem` that lives in the system menu bar.
///
/// Lifecycle is fully reversible: `install()` creates and shows the status item;
/// `uninstall()` removes it from the menu bar so toggling the AppStorage flag
/// makes the icon vanish immediately. The controller observes `DiskPressureMonitor`
/// to update its icon and text, and presents a SwiftUI popover on click.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    @Published private(set) var pressureLevel: DiskPressureLevel = .healthy
    @Published private(set) var diskUsage: DiskUsageInfo?
    /// Last time we kicked off a `viewModel.scanAll()` — used to avoid spamming
    /// scans every time the user pops the menu bar open.
    @Published private(set) var lastScanAt: Date?

    private weak var viewModel: CleanupViewModel?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    private let monitor: DiskPressureMonitor
    private let notificationService = NotificationService()
    private var monitorTask: Task<Void, Never>?
    private var previousLevel: DiskPressureLevel = .healthy

    /// User-visible toggle. `@AppStorage` keeps this in sync with the Settings UI.
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage("menuBarShowSize") private var menuBarShowSize = false
    @AppStorage("menuBarPollSeconds") private var menuBarPollSeconds: Double = 60

    private var settingsCancellables = Set<AnyCancellable>()

    init(viewModel: CleanupViewModel) {
        self.viewModel = viewModel
        self.monitor = DiskPressureMonitor(pollSeconds: 60)
        super.init()

        observeDefaults()
        Task { await monitor.setPollSeconds(menuBarPollSeconds) }
    }

    deinit {
        monitorTask?.cancel()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Public lifecycle

    /// Boots monitoring and, if enabled, installs the status item. Call once
    /// after the app finishes launching.
    func bootstrap() {
        Task { await monitor.start() }
        startMonitorListener()
        if menuBarEnabled {
            install()
        }
    }

    /// Tear everything down. Call from `applicationWillTerminate`.
    func shutdown() {
        Task { await monitor.stop() }
        monitorTask?.cancel()
        uninstall()
    }

    // MARK: - Status item lifecycle

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            // Receive both left- and right-clicks; we handle disambiguation below.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacCleaner — disk usage at a glance"
        }
        self.statusItem = item
        refreshStatusItem()
    }

    func uninstall() {
        closePopover()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Defaults observation

    private func observeDefaults() {
        // React to toggle changes in real time. `@AppStorage` writes through
        // UserDefaults, so we observe `.didChangeNotification` rather than KVO
        // (KVO on UserDefaults requires the exact key path).
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDefaultsChanged() }
            .store(in: &settingsCancellables)
    }

    private func handleDefaultsChanged() {
        if menuBarEnabled {
            if statusItem == nil { install() } else { refreshStatusItem() }
        } else {
            uninstall()
        }
        // Cadence is clamped 30…600 inside the actor.
        Task { await monitor.setPollSeconds(menuBarPollSeconds) }
        refreshStatusItem()
    }

    // MARK: - Pressure monitor consumption

    private func startMonitorListener() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in await self.monitor.events() {
                if Task.isCancelled { return }
                await self.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: DiskPressureSnapshot) async {
        let previous = previousLevel
        previousLevel = snapshot.level
        pressureLevel = snapshot.level
        diskUsage = snapshot.usage
        refreshStatusItem()

        // Notify only on transitions into critical, never on every poll.
        if previous != .critical, snapshot.level == .critical, let usage = snapshot.usage {
            await notificationService.checkAndNotifyLowStorage(usage)
        }
    }

    // MARK: - Status item rendering

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let symbolName = pressureLevel.sfSymbolName
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config)
        image?.isTemplate = (pressureLevel != .critical)
        button.image = image

        // Critical state gets a non-template tint so the red is preserved by
        // the system menu bar (template images are recolored to match the bar).
        if pressureLevel == .critical {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }

        // Optional inline GB readout — only shown when the user opted in AND
        // we're not in the healthy state (the icon alone is enough then).
        if menuBarShowSize, pressureLevel != .healthy, let used = diskUsage?.usedSpace {
            button.title = " " + ByteFormatter.format(used)
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }

        button.setAccessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch pressureLevel {
        case .healthy:  return "MacCleaner: disk usage healthy"
        case .low:      return "MacCleaner: disk usage low — consider cleaning"
        case .critical: return "MacCleaner: disk usage critical"
        }
    }

    // MARK: - Click handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open MacCleaner", action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacCleaner", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem?.menu = menu
        button.performClick(nil)
        // Detach so left-click goes back to popover behavior on next click.
        statusItem?.menu = nil
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if let popover, popover.isShown {
            closePopover()
            return
        }
        showPopover(from: button)
    }

    private func showPopover(from button: NSStatusBarButton) {
        guard let viewModel else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let view = MenuBarPopoverView(
            controller: self,
            onClose: { [weak self] in self?.closePopover() }
        )
        .environmentObject(viewModel)

        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: 320, height: 420)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 320, height: 420)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        // Dismiss on clicks outside the popover (reinforces .transient behavior
        // for clicks the system doesn't route through the popover).
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }

        triggerScanIfStale()
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Kick off `scanAll()` only if the data is meaningfully stale and we're
    /// not already scanning — protects against the popover being opened many
    /// times in a row.
    private func triggerScanIfStale() {
        guard let viewModel else { return }
        guard !viewModel.isScanning, !viewModel.isCleaning else { return }

        let staleEnough: Bool = {
            if viewModel.totalReclaimable == 0 { return true }
            guard let lastScanAt else { return true }
            return Date().timeIntervalSince(lastScanAt) > 60
        }()

        guard staleEnough else { return }

        lastScanAt = Date()
        Task { @MainActor [weak viewModel] in
            await viewModel?.scanAll()
        }
    }

    // MARK: - Menu actions

    @objc func openMainWindow() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)

        // Prefer an existing main-style window. We exclude the status item's
        // popover window and any panels/menus by requiring `canBecomeMain`.
        let mainWindow = NSApp.windows.first { window in
            guard window.canBecomeMain else { return false }
            if window.isExcludedFromWindowsMenu { return false }
            return window.contentViewController != nil
        }

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Fall back to AppKit's standard "open a new document" path, which
            // SwiftUI's WindowGroup hooks to spawn a fresh window.
            NSApp.sendAction(NSSelectorFromString("newDocument:"), to: nil, from: nil)
        }
    }

    @objc func openSettings() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func hideMenuBarIcon() {
        menuBarEnabled = false
        uninstall()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Quick actions invoked from the popover

    func emptyTrash() async -> Int64 {
        guard let viewModel else { return 0 }
        if let trashCategory = viewModel.categories.first(where: { $0.type == .trash }) {
            await viewModel.cleanSingle(trashCategory)
            return viewModel.cleanupSummary?.totalBytesFreed ?? 0
        }
        return 0
    }

    func flushDNS() async -> Int64 {
        guard let viewModel else { return 0 }
        if let dnsCategory = viewModel.categories.first(where: { $0.type == .dnsCache }) {
            await viewModel.cleanSingle(dnsCategory)
            return viewModel.cleanupSummary?.totalBytesFreed ?? 0
        }
        return 0
    }
}
