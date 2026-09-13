import AppKit
import HouseKit

extension SettingsWindowController {
    /// Put.io · Library · Automation · General · About.
    static func cargo(coordinator: CargoCoordinator) -> SettingsWindowController {
        SettingsWindowController(appName: "Cargo", pages: [
            SettingsPage("Put.io", symbol: "icloud.and.arrow.down", controller: PutIOPage(coordinator: coordinator)),
            SettingsPage("Library", symbol: "externaldrive", controller: LibraryPage(coordinator: coordinator)),
            SettingsPage("Automation", symbol: "gearshape.2", controller: AutomationPage(coordinator: coordinator)),
            SettingsPage("General", symbol: "gearshape", controller: GeneralPage(
                launchAtLogin: (
                    get: { coordinator.state.settings.launchAtLoginEnabled },
                    set: { value in try? coordinator.updateSettings { $0.launchAtLoginEnabled = value } }
                )
            )),
            SettingsPage("About", symbol: "info.circle", controller: AboutPage(
                appName: "Cargo",
                tagline: "Put.io → SSD → Infuse, without touching it."
            ))
        ])
    }
}

/// A form that re-reads coordinator state whenever it changes. Every control
/// saves on change; `status` shows the last save or error.
@MainActor
class CargoPage: SettingsForm {
    let coordinator: CargoCoordinator
    let statusLabel = SettingsForm.caption("")

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        build()
        refresh()
    }

    func build() {}
    func refresh() {}

    @objc private func coordinatorDidChange() {
        refresh()
    }

    func save(_ mutate: (inout CargoSettings) throws -> Void) {
        do {
            try coordinator.updateSettings(mutate)
            statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
            refresh()
        }
    }

    /// True while the user is typing in `field`, so refresh doesn't clobber it.
    func isEditing(_ field: NSTextField) -> Bool {
        view.window?.firstResponder === field.currentEditor()
    }
}

// MARK: - Put.io

final class PutIOPage: CargoPage {
    private lazy var connectButton = SettingsForm.button("Connect with Put.io…", target: self, action: #selector(connect))
    private lazy var disconnectButton = SettingsForm.button("Disconnect", target: self, action: #selector(disconnect))
    private let accountLabel = SettingsForm.caption("")
    private let intervalPopup = SettingsForm.popup()

    override func build() {
        section("Account")
        row("Status", accountLabel)
        row(nil, [connectButton, disconnectButton])
        note("Authorization happens in the browser and returns through cargo://oauth/callback. The token lives in Keychain, never in the state file or logs.")

        section("Polling")
        for minutes in CargoSettings.refreshIntervalChoices {
            intervalPopup.addItem(withTitle: minutes == 1 ? "1 minute" : "\(minutes) minutes")
            intervalPopup.lastItem?.tag = minutes
        }
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        row("Check Put.io every", intervalPopup)
        row(nil, statusLabel)
    }

    override func refresh() {
        let connected = coordinator.isConnected
        connectButton.isHidden = connected
        disconnectButton.isHidden = !connected
        accountLabel.stringValue = coordinator.putIOStatus
        intervalPopup.selectItem(withTag: coordinator.state.settings.refreshIntervalMinutes)
    }

    @objc private func connect() {
        do {
            NSWorkspace.shared.open(try coordinator.beginPutIOAuthorization())
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func disconnect() {
        do {
            try coordinator.removePutIOToken()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func intervalChanged() {
        let minutes = intervalPopup.selectedTag()
        save { $0.refreshIntervalMinutes = minutes }
    }
}

// MARK: - Library

final class LibraryPage: CargoPage, NSTextFieldDelegate, NSPathControlDelegate {
    private let libraryPath = NSPathControl()
    private let stagingField = SettingsForm.textField(width: 220)
    private let moviesField = SettingsForm.textField(width: 220)
    private let tvShowsField = SettingsForm.textField(width: 220)
    private let watchlistURLField = SettingsForm.textField(placeholder: "https://www.imdb.com/user/…/watchlist/", width: 300)
    private let watchlistStatusLabel = SettingsForm.caption("")

    override func build() {
        section("Local library")
        // Pop-up path control: shows the chosen folder, click to choose, drop a folder to set.
        libraryPath.pathStyle = .popUp
        libraryPath.controlSize = .small
        libraryPath.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        libraryPath.placeholderString = "Choose the folder Infuse reads…"
        libraryPath.delegate = self
        libraryPath.target = self
        libraryPath.action = #selector(libraryPathChanged)
        libraryPath.widthAnchor.constraint(equalToConstant: 300).isActive = true
        row("Library folder", libraryPath)
        note("The folder Infuse reads. Cargo never rearranges it; it only adds into the folders below.")
        for (title, field) in [("Staging folder", stagingField), ("Movies folder", moviesField), ("TV Shows folder", tvShowsField)] {
            field.delegate = self
            row(title, field)
        }

        section("IMDb Watchlist")
        watchlistURLField.delegate = self
        let refresh = SettingsForm.button("Refresh", target: self, action: #selector(refreshWatchlistNow))
        let open = SettingsForm.button("Edit on IMDb…", target: self, action: #selector(openWatchlist))
        row("Public list URL", [watchlistURLField, refresh, open])
        row(nil, watchlistStatusLabel)
        row(nil, statusLabel)
    }

    override func refresh() {
        let settings = coordinator.state.settings
        libraryPath.url = settings.libraryRootPath.map { URL(fileURLWithPath: $0) }
        for (field, value) in [(stagingField, settings.stagingDirectoryName), (moviesField, settings.moviesDirectoryName), (tvShowsField, settings.tvShowsDirectoryName)]
        where !isEditing(field) {
            field.stringValue = value
        }
        if !isEditing(watchlistURLField) { watchlistURLField.stringValue = settings.imdbWatchlistURL }
        watchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus
    }

    func pathControl(_ pathControl: NSPathControl, willDisplay openPanel: NSOpenPanel) {
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Use as Library Root"
        openPanel.message = "Choose the folder on the SSD that Infuse reads."
    }

    func pathControl(_ pathControl: NSPathControl, acceptDrop info: any NSDraggingInfo) -> Bool {
        guard let url = NSURL(from: info.draggingPasteboard) as URL?,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return false }
        pathControl.url = url
        libraryPathChanged()
        return true
    }

    @objc private func libraryPathChanged() {
        guard let url = libraryPath.url, url.path != coordinator.state.settings.libraryRootPath else { return }
        do {
            try coordinator.saveLibraryRoot(url)
        } catch {
            NSAlert(error: error).runModal()
            refresh()
        }
    }

    @objc private func openWatchlist() {
        commitWatchlistURL()
        guard let url = URL(string: coordinator.state.settings.imdbWatchlistURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshWatchlistNow() {
        commitWatchlistURL()
        Task { _ = await coordinator.refreshIMDbWatchlist() }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === watchlistURLField {
            commitWatchlistURL()
        } else {
            commitDirectoryNames()
        }
    }

    private func commitWatchlistURL() {
        let value = watchlistURLField.stringValue
        guard value != coordinator.state.settings.imdbWatchlistURL else { return }
        do {
            try coordinator.saveIMDbWatchlistURL(value)
            statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func commitDirectoryNames() {
        let settings = coordinator.state.settings
        guard stagingField.stringValue != settings.stagingDirectoryName
            || moviesField.stringValue != settings.moviesDirectoryName
            || tvShowsField.stringValue != settings.tvShowsDirectoryName else { return }
        do {
            try coordinator.saveDirectorySettings(
                staging: stagingField.stringValue,
                movies: moviesField.stringValue,
                tvShows: tvShowsField.stringValue
            )
            statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
            refresh()
        }
    }
}

// MARK: - Automation

final class AutomationPage: CargoPage {
    private var switches: [(NSSwitch, WritableKeyPath<CargoSettings, Bool>)] = []

    override func build() {
        section("Background cycle")
        let toggles: [(String, WritableKeyPath<CargoSettings, Bool>)] = [
            ("Sync new completed Put.io media", \.automaticSyncEnabled),
            ("Organize and rename Inbox media", \.automaticOrganizationEnabled),
            ("Delete Put.io file after verified local copy", \.automaticRemoteCleanupEnabled),
            ("Remove Inbox sidecars and empty folders", \.automaticInboxCleanupEnabled)
        ]
        for (title, keyPath) in toggles {
            let control = toggle(title, isOn: coordinator.state.settings[keyPath: keyPath]) { [weak self] value in
                self?.save { $0[keyPath: keyPath] = value }
            }
            switches.append((control, keyPath))
        }
        note("Put.io deletion happens only after a verified local copy. Inbox cleanup removes non-media sidecars only when a nested folder has no media or subfolders left.")

        section("Notifications")
        let notifications = toggle("Send notifications", isOn: coordinator.state.settings.notificationsEnabled) { [weak self] value in
            self?.save { $0.notificationsEnabled = value }
        }
        switches.append((notifications, \.notificationsEnabled))
        row(nil, statusLabel)
    }

    override func refresh() {
        let settings = coordinator.state.settings
        for (control, keyPath) in switches {
            control.state = settings[keyPath: keyPath] ? .on : .off
        }
    }
}
