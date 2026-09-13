import AppKit

@main
@MainActor
final class CargoAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusHeaderItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshTask: Task<Void, Never>?
    private let coordinator = CargoCoordinator()
    private let notificationService = CargoNotificationService()
    private lazy var mainWindowController = MainWindowController(coordinator: coordinator)
    private lazy var settingsWindowController = SettingsWindowController(coordinator: coordinator)

    static func main() {
        let application = NSApplication.shared
        let delegate = CargoAppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.mainMenu = makeMainMenu()
        notificationService.requestAuthorization()
        try? LaunchAtLoginManager.shared.setEnabled(coordinator.state.settings.launchAtLoginEnabled)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Cargo menu")
            button.toolTip = "Cargo"
        }

        // Action-first menu with visible shortcuts, same shape as Tessellate's.
        statusMenu = NSMenu()
        statusHeaderItem = NSMenuItem.sectionHeader(title: "Cargo")
        statusMenu.addItem(statusHeaderItem)
        statusMenu.addItem(NSMenuItem(title: "Open Cargo", action: #selector(showDashboard(_:)), keyEquivalent: "o"))
        statusMenu.addItem(NSMenuItem(title: "Add Transfer…", action: #selector(addTransfer(_:)), keyEquivalent: "n"))
        statusMenu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshNow(_:)), keyEquivalent: "r"))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ","))
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        statusMenu.addItem(launchAtLoginItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit Cargo", action: #selector(quitCargo(_:)), keyEquivalent: "q"))
        statusMenu.items.forEach { $0.target = self }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.isVisible = true

        mainWindowController.openSettings = { [weak self] in self?.settingsWindowController.show() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        updateStatusMenu()
        mainWindowController.show()
        startBackgroundCycle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == PutIOOAuth.redirectURI.scheme {
            Task { @MainActor in
                do {
                    try await coordinator.finishPutIOAuthorization(from: url)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindowController.show() }
        return true
    }

    // MARK: - Background cycle

    private func startBackgroundCycle() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let summary = await coordinator.runBackgroundCycle()
                notify(summary)
                let minutes = max(1, coordinator.state.settings.refreshIntervalMinutes)
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    @objc private func coordinatorDidChange() {
        updateStatusMenu()
    }

    // MARK: - Menus

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "Cargo")
        appMenu.addItem(withTitle: "About Cargo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Cargo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Cargo", action: #selector(quitCargo(_:)), keyEquivalent: "q").target = self
        mainMenu.addItem(withTitle: "Cargo", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Cargo", action: #selector(showDashboard(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Add Transfer…", action: #selector(addTransfer(_:)), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Add Transfer from Clipboard", action: #selector(pasteTransfer(_:)), keyEquivalent: "V").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Refresh", action: #selector(refreshNow(_:)), keyEquivalent: "r").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        let viewMenu = NSMenu(title: "View")
        for page in Page.allCases {
            let item = viewMenu.addItem(
                withTitle: page.title,
                action: #selector(MainWindowController.selectPage(_:)),
                keyEquivalent: String(page.rawValue + 1)
            )
            item.tag = page.rawValue
            item.target = mainWindowController
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .control]
        mainMenu.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = viewMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        mainMenu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard statusMenu != nil else { return }
        let state = coordinator.state
        var parts: [String] = []
        parts.append(coordinator.isConnected
            ? coordinator.putIOStatus.replacingOccurrences(of: "Connected as ", with: "")
            : "Not connected")
        if !state.transfers.isEmpty { parts.append("\(state.transfers.count) transfers") }
        let inboxCount = coordinator.inboxFileURLs().count
        if inboxCount > 0 { parts.append("\(inboxCount) in Inbox") }
        statusHeaderItem.title = parts.joined(separator: " · ")
        launchAtLoginItem.state = state.settings.launchAtLoginEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc func showDashboard(_ sender: Any?) {
        mainWindowController.show()
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc func addTransfer(_ sender: Any?) {
        mainWindowController.show()
        mainWindowController.addTransfer(sender)
    }

    @objc func pasteTransfer(_ sender: Any?) {
        mainWindowController.show()
        mainWindowController.pasteTransfer(sender)
    }

    @objc func refreshNow(_ sender: Any?) {
        mainWindowController.refreshNow(sender)
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        let enabled = !coordinator.state.settings.launchAtLoginEnabled
        do {
            try coordinator.updateSettings { $0.launchAtLoginEnabled = enabled }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func quitCargo(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func notify(_ summary: CargoBackgroundCycleSummary) {
        guard coordinator.state.settings.notificationsEnabled, summary.hasMeaningfulChanges else { return }

        func plural(_ count: Int, _ noun: String, _ pluralNoun: String? = nil) -> String {
            "\(count) \(count == 1 ? noun : (pluralNoun ?? noun + "s"))"
        }
        var lines: [String] = []
        if !summary.discovered.isEmpty { lines.append("Found \(plural(summary.discovered.count, "new media item"))") }
        if !summary.watchlistAdded.isEmpty { lines.append("Watchlist added \(plural(summary.watchlistAdded.count, "title"))") }
        if !summary.deleted.isEmpty { lines.append("Removed \(plural(summary.deleted.count, "remote file"))") }
        if !summary.deletedFolders.isEmpty { lines.append("Removed \(plural(summary.deletedFolders.count, "empty folder"))") }
        if !summary.organized.isEmpty {
            lines.append("Organized \(plural(summary.organized.count, "item"))")
        } else if !summary.downloaded.isEmpty {
            lines.append("Downloaded \(plural(summary.downloaded.count, "item")) to Inbox")
        }
        if !summary.failures.isEmpty {
            lines.append(summary.failures.count == 1 ? "1 item needs attention" : "\(summary.failures.count) items need attention")
        }
        notificationService.post(title: "Cargo workflow updated", body: lines.joined(separator: " · "))
    }

    /// The app icon scaled for the menu bar, full color — house style shared with
    /// Tessellate and Headroom. The icon's plate spans 824/1024 of the artwork; scale
    /// so it lands at 16pt inside the 18pt canvas, the shared menu bar plate size.
    private static let menuBarIcon: NSImage = {
        let source = NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 18, height: 18))
        let size = NSSize(width: 18, height: 18)
        let plateFraction: CGFloat = 824 / 1024
        let drawSize = 16 / plateFraction
        let drawRect = NSRect(x: (size.width - drawSize) / 2, y: (size.height - drawSize) / 2, width: drawSize, height: drawSize)
        let resized = NSImage(size: size, flipped: false) { _ in
            source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        resized.isTemplate = false
        return resized
    }()
}
