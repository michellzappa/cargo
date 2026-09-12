import AppKit

@main
@MainActor
final class CargoAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var dashboardWindowController: NSWindowController?
    private var dashboardViewController: DashboardViewController!
    private var refreshTask: Task<Void, Never>?
    private let coordinator = CargoCoordinator()
    private let notificationService = CargoNotificationService()

    static func main() {
        let application = NSApplication.shared
        let delegate = CargoAppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        notificationService.requestAuthorization()
        try? LaunchAtLoginManager.shared.setEnabled(coordinator.state.settings.launchAtLoginEnabled)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "shippingbox",
                accessibilityDescription: "Cargo"
            )
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 16, height: 16)
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Cargo menu")
            button.target = self
            button.action = #selector(statusItemAction(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Cargo"
        }

        statusMenu = NSMenu()
        statusMenu.addItem(
            NSMenuItem(title: "Open Cargo", action: #selector(showDashboard(_:)), keyEquivalent: "")
        )
        statusMenu.addItem(
            NSMenuItem(title: "Settings", action: #selector(showSettings(_:)), keyEquivalent: ",")
        )
        statusMenu.addItem(
            NSMenuItem(title: "Refresh Now", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            NSMenuItem(title: "Quit Cargo", action: #selector(quitCargo(_:)), keyEquivalent: "q")
        )
        statusMenu.items.forEach { $0.target = self }

        showDashboardWindow()

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let summary = await coordinator.runBackgroundCycle()
                notify(summary)
                dashboardViewController.refreshView()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == PutIOOAuth.redirectURI.scheme {
            Task { @MainActor in
                do {
                    try await coordinator.finishPutIOAuthorization(from: url)
                    dashboardViewController.refreshView()
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showDashboardWindow()
        }
        return true
    }

    @objc private func showDashboard(_ sender: Any?) {
        showDashboardWindow()
    }

    @objc private func statusItemAction(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let shouldShowMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if shouldShowMenu {
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height),
                in: sender
            )
        } else {
            showDashboardWindow()
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        showDashboardWindow()
        dashboardViewController.showSettings()
    }

    @objc private func refreshNow(_ sender: Any?) {
        Task { @MainActor in
            let summary = await coordinator.runBackgroundCycle()
            notify(summary)
            dashboardViewController.refreshView()
        }
    }

    @objc private func quitCargo(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showDashboardWindow() {
        if let dashboardWindowController {
            dashboardWindowController.showWindow(nil)
            dashboardWindowController.window?.orderFrontRegardless()
            dashboardWindowController.window?.makeKeyAndOrderFront(nil)
        } else {
            dashboardViewController = DashboardViewController(coordinator: coordinator)
            let window = NSWindow(contentViewController: dashboardViewController)
            window.title = "Cargo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.minSize = NSSize(width: 680, height: 420)
            window.center()
            window.isReleasedWhenClosed = false
            dashboardWindowController = NSWindowController(window: window)
            dashboardWindowController?.showWindow(nil)
            dashboardWindowController?.window?.orderFrontRegardless()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func notify(_ summary: CargoBackgroundCycleSummary) {
        guard coordinator.state.settings.notificationsEnabled,
              summary.hasMeaningfulChanges else {
            return
        }

        var lines: [String] = []
        if !summary.discovered.isEmpty {
            lines.append("Found \(summary.discovered.count) new media item\(summary.discovered.count == 1 ? "" : "s")")
        }
        if !summary.watchlistAdded.isEmpty {
            lines.append("Watchlist added \(summary.watchlistAdded.count) title\(summary.watchlistAdded.count == 1 ? "" : "s")")
        }
        if !summary.deleted.isEmpty {
            lines.append("Removed \(summary.deleted.count) remote file\(summary.deleted.count == 1 ? "" : "s")")
        }
        if !summary.deletedFolders.isEmpty {
            lines.append("Removed \(summary.deletedFolders.count) empty folder\(summary.deletedFolders.count == 1 ? "" : "s")")
        }
        if !summary.organized.isEmpty {
            lines.append("Organized \(summary.organized.count) item\(summary.organized.count == 1 ? "" : "s")")
        } else if !summary.downloaded.isEmpty {
            lines.append("Downloaded \(summary.downloaded.count) item\(summary.downloaded.count == 1 ? "" : "s") to Inbox")
        }
        if !summary.failures.isEmpty {
            lines.append("\(summary.failures.count) item\(summary.failures.count == 1 ? " needs" : " items need") attention")
        }

        notificationService.post(
            title: "Cargo workflow updated",
            body: lines.joined(separator: " · ")
        )
    }
}
