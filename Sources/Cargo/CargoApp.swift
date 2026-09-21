import AppKit
import HouseKit

@main
@MainActor
final class CargoAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusHeaderItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshTask: Task<Void, Never>?
    private let coordinator = CargoCoordinator()
    private let keychainStore = KeychainStore()
    private let notificationService = CargoNotificationService()
    private lazy var mainWindowController = MainWindowController(coordinator: coordinator)
    private var remoteAccessPage: RemoteAccessPage?
    private lazy var settingsWindowController = SettingsWindowController.cargo(coordinator: coordinator) { [weak self] page in
        self?.remoteAccessPage = page
    }
    private lazy var remoteAPIController = CargoRemoteController(coordinator: coordinator)
    private let remoteAPIEventFeed = CargoRemoteEventFeed()
    private var remoteAPIServer: CargoHTTPServer?
    private var remoteAPIToken: String?
    private var remoteAPIScope: CargoRemoteNetworkScope?

    static func main() {
        let application = NSApplication.shared
        let delegate = CargoAppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cargo is resident in the menu bar when it has no UI open. A window
        // promotes it to a normal foreground app; see MainWindowController.
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.mainMenu = makeMainMenu()
        notificationService.requestAuthorization()
        if LaunchAtLogin.isEnabled != coordinator.state.settings.launchAtLoginEnabled {
            try? LaunchAtLogin.setEnabled(coordinator.state.settings.launchAtLoginEnabled)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarPlate.image(glyph: HouseGlyphs.cargo)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Cargo menu")
            button.toolTip = "Cargo"
        }

        startRemoteAPI()
        startRemoteClientIfConfigured()
        if !coordinator.isChillConnected, coordinator.chillStatus.hasPrefix("Token saved") {
            Task { await coordinator.verifyChillConnection() }
        }

        // House menu: header, the actions, then the shared tail.
        statusMenu = NSMenu()
        statusHeaderItem = StatusMenu.sectionHeader("Cargo")
        statusMenu.addItem(statusHeaderItem)
        statusMenu.addItem(NSMenuItem(title: "Open Cargo", action: #selector(showDashboard(_:)), keyEquivalent: "o"))
        statusMenu.addItem(NSMenuItem(title: "Add Transfer…", action: #selector(addTransfer(_:)), keyEquivalent: "n"))
        statusMenu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshNow(_:)), keyEquivalent: "r"))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Edit Watchlist on IMDb…", action: #selector(openWatchlist(_:)), keyEquivalent: "i"))
        statusMenu.items.forEach { $0.target = self }
        StatusMenu.appendStandardTail(
            to: statusMenu,
            appName: "Cargo",
            target: self,
            settings: #selector(showSettings(_:)),
            launchAtLogin: #selector(toggleLaunchAtLogin(_:)),
            launchAtLoginEnabled: coordinator.state.settings.launchAtLoginEnabled,
            quit: #selector(quitCargo(_:))
        )
        launchAtLoginItem = statusMenu.items.first { $0.title == "Launch at Login" }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.isVisible = true

        mainWindowController.openSettings = { [weak self] in self?.showSettings(nil) }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        updateStatusMenu()
        // A login item should not put a window up; only when there is nothing
        // to run yet does the dashboard open by itself.
        if !coordinator.isConnected { mainWindowController.show() }
        startBackgroundCycle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        remoteAPIServer?.stop()
        Task { await coordinator.remoteClientSession.disconnect() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == PutIOOAuth.redirectURI.scheme {
            switch url.host {
            case "oauth":
                Task { @MainActor in
                    do {
                        try await coordinator.finishPutIOAuthorization(from: url)
                    } catch {
                        NSAlert(error: error).runModal()
                    }
                }
            case "settings":
                showSettings(nil)
            case "pair":
                // cargo://pair?url=…&token=… — the resident's pairing link, opened directly.
                guard let link = CargoPairingLink(parsing: url) else { break }
                showSettings(nil)
                settingsWindowController.show(page: 4) // Remote Access
                remoteAccessPage?.connect(with: link)
            case "open":
                // cargo://open?page=library
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
                mainWindowController.show(page: Page.allCases.first { $0.title.lowercased() == name?.lowercased() })
            case "snapshot":
                // cargo://snapshot?page=library&to=/path.png — debugging aid: renders the window to a PNG.
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let name = items.first { $0.name == "page" }?.value
                let path = items.first { $0.name == "to" }?.value ?? NSTemporaryDirectory() + "cargo-snapshot.png"
                mainWindowController.show(page: Page.allCases.first { $0.title.lowercased() == name?.lowercased() })
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [mainWindowController] in
                    guard let view = mainWindowController.window?.contentView?.superview,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            default:
                break
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindowController.show() }
        return true
    }

    // MARK: - Background cycle

    private func startRemoteAPI() {
        remoteAPIServer?.stop()
        remoteAPIServer = nil
        do {
            let token = try keychainStore.ensureRemoteAPIToken()
            let scope = coordinator.state.settings.remoteNetworkScope
            let router = CargoRemoteAPIRouter(
                controller: remoteAPIController,
                token: token,
                eventFeed: remoteAPIEventFeed,
                presenceRegistry: coordinator.remotePresenceRegistry
            )
            let configuration = CargoHTTPServer.Configuration(
                host: scope.bindHost,
                port: CargoHTTPServer.Configuration.defaultPort
            )
            let server = CargoHTTPServer(configuration: configuration) { request in
                await router.handle(request)
            }
            try server.start()
            remoteAPIServer = server
            remoteAPIToken = token
            remoteAPIScope = scope
        } catch {
            remoteAPIToken = nil
            remoteAPIScope = nil
            NSLog("Cargo remote API could not start: %@", error.localizedDescription)
        }
    }

    private func startRemoteClientIfConfigured() {
        let settings = coordinator.state.settings
        guard settings.remoteClientEnabled, !settings.remoteServerURL.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.remoteClientSession.connect(
                baseURLString: settings.remoteServerURL,
                token: keychainStore.readRemoteClientToken() ?? ""
            )
        }
    }

    private func restartRemoteAPIIfNeeded() {
        let scope = coordinator.state.settings.remoteNetworkScope
        let token = keychainStore.readRemoteAPIToken()
        guard remoteAPIScope == scope, remoteAPIToken != nil, remoteAPIToken == token else {
            startRemoteAPI()
            return
        }
    }

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
        remoteAPIEventFeed.publish()
        restartRemoteAPIIfNeeded()
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
        appMenu.addItem(withTitle: "Close Cargo", action: #selector(closeToMenuBar(_:)), keyEquivalent: "q").target = self
        mainMenu.addItem(withTitle: "Cargo", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Cargo", action: #selector(showDashboard(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Add Transfer…", action: #selector(addTransfer(_:)), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Add Transfer from Clipboard", action: #selector(pasteTransfer(_:)), keyEquivalent: "V").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Refresh", action: #selector(refreshNow(_:)), keyEquivalent: "r").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Edit Watchlist on IMDb…", action: #selector(openWatchlist(_:)), keyEquivalent: "i").target = self
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
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Search Cargo…", action: #selector(MainWindowController.showSearch(_:)), keyEquivalent: "k").target = mainWindowController
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
        let state = coordinator.dashboardState
        var parts: [String] = []
        parts.append(coordinator.dashboardIsConnected
            ? coordinator.dashboardPutIOStatus.replacingOccurrences(of: "Connected as ", with: "")
            : "Not connected")
        if !state.transfers.isEmpty { parts.append("\(state.transfers.count) transfers") }
        let inboxCount = coordinator.isRemoteClientMode
            ? state.localJobs.filter { $0.status != .completed }.count
            : coordinator.inboxFileURLs().count
        if inboxCount > 0 { parts.append("\(inboxCount) in Inbox") }
        statusHeaderItem.title = parts.joined(separator: " · ")
        launchAtLoginItem.state = state.settings.launchAtLoginEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc func showDashboard(_ sender: Any?) {
        mainWindowController.show()
    }

    @objc func showSettings(_ sender: Any?) {
        showAsRegularApp()
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

    /// The configured IMDb list, in the browser — that is where the list is edited.
    @objc func openWatchlist(_ sender: Any?) {
        guard let url = URL(string: coordinator.state.settings.imdbWatchlistURL) else { return }
        NSWorkspace.shared.open(url)
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

    /// ⌘Q closes the normal app UI but leaves Cargo's background services and
    /// menu-bar item running. The explicit Quit action in the status menu is
    /// still a real termination path.
    @objc private func closeToMenuBar(_ sender: Any?) {
        for window in NSApp.windows where window.isVisible {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
    }

    private func showAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
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
        if !summary.extracting.isEmpty { lines.append("Unpacking \(plural(summary.extracting.count, "archive"))") }
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
}
