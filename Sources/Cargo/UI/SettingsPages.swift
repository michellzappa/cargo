import AppKit
import EasySubsKit
import HouseKit

extension SettingsWindowController {
    /// Put.io · Chill · Library · Automation · General · About.
    static func cargo(
        coordinator: CargoCoordinator,
        remoteAccessPage: ((RemoteAccessPage) -> Void)? = nil
    ) -> SettingsWindowController {
        let remoteAccess = RemoteAccessPage(coordinator: coordinator)
        remoteAccessPage?(remoteAccess)
        let startPageControl = CargoStartPageControl(coordinator: coordinator)
        return SettingsWindowController(appName: "Cargo", pages: [
            SettingsPage("Put.io", symbol: "icloud.and.arrow.down", controller: PutIOPage(coordinator: coordinator)),
            SettingsPage("Chill", symbol: "sparkles", controller: ChillPage(coordinator: coordinator)),
            SettingsPage("Library", symbol: "externaldrive", controller: LibraryPage(coordinator: coordinator)),
            SettingsPage("Automation", symbol: "gearshape.2", controller: AutomationPage(coordinator: coordinator)),
            SettingsPage("Remote Access", symbol: "network", controller: remoteAccess),
            SettingsPage("General", symbol: "gearshape", controller: GeneralPage(
                launchAtLogin: (
                    get: { coordinator.state.settings.launchAtLoginEnabled },
                    set: { value in try? coordinator.updateSettings { $0.launchAtLoginEnabled = value } }
                ),
                permissions: [.notifications],
                extras: { form in startPageControl.add(to: form) }
            )),
            SettingsPage("About", symbol: "info.circle", controller: AboutPage(
                appName: "Cargo",
                tagline: "Put.io → SSD → Infuse, without touching it.",
                links: [("GitHub", URL(string: "https://github.com/michellzappa/cargo")!)]
            ))
        ])
    }
}

@MainActor
private final class CargoStartPageControl: NSObject {
    private let coordinator: CargoCoordinator
    private let popup = SettingsForm.popup()

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        super.init()
        for page in CargoStartPage.allCases {
            popup.addItem(withTitle: page.displayName)
            popup.lastItem?.representedObject = page
        }
        popup.target = self
        popup.action = #selector(changed(_:))
    }

    func add(to form: SettingsForm) {
        form.section("Dashboard")
        form.row("Start in", popup)
        form.note("Choose the page Cargo opens when the main window appears.")
        refresh()
    }

    private func refresh() {
        let page = coordinator.state.settings.startPage
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? CargoStartPage) == page }) {
            popup.selectItem(at: index)
        }
    }

    @objc private func changed(_ sender: NSPopUpButton) {
        guard let page = sender.selectedItem?.representedObject as? CargoStartPage else { return }
        try? coordinator.updateSettings { $0.startPage = page }
    }
}

// MARK: - Remote Access

final class RemoteAccessPage: CargoPage {
    private let scopePopup = SettingsForm.popup()
    private let endpointLabel = SettingsForm.caption("")
    private let tokenLabel = SettingsForm.caption("")
    private let serverURLField = SettingsForm.textField(
        placeholder: "cargo://pair?… or http://192.168.1.20:39817",
        width: 300
    )
    private let clientNameField = SettingsForm.textField(
        placeholder: "This device",
        width: 180
    )
    private let remoteTokenField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "Paste the resident token"
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return field
    }()
    private let clientStatusLabel = SettingsForm.caption("")
    private let clientsLabel = SettingsForm.caption("")
    private let tailscalePopup = SettingsForm.popup()
    private lazy var copyTokenButton = SettingsForm.button("Copy token", target: self, action: #selector(copyToken))
    private lazy var copyPairingLinkButton = SettingsForm.button("Copy pairing link", target: self, action: #selector(copyPairingLink))
    private lazy var rotateTokenButton = SettingsForm.button("Rotate…", target: self, action: #selector(rotateToken))
    private lazy var connectClientButton = SettingsForm.button("Connect", target: self, action: #selector(connectClient))
    private lazy var disconnectClientButton = SettingsForm.button("Disconnect", target: self, action: #selector(disconnectClient))
    private lazy var findTailscaleButton = SettingsForm.button("Find servers", target: self, action: #selector(findTailscaleServers))
    private var discoveredTailscaleServers: [CargoTailscaleServer] = []

    override func build() {
        section("Resident API")
        for scope in CargoRemoteNetworkScope.allCases {
            scopePopup.addItem(withTitle: scope.displayName)
            scopePopup.lastItem?.representedObject = scope.rawValue
        }
        scopePopup.target = self
        scopePopup.action = #selector(scopeChanged)
        row("Network", scopePopup)
        row("Endpoint", endpointLabel)
        row("Token", [tokenLabel, copyTokenButton, rotateTokenButton])
        row("Pair a client", copyPairingLinkButton)
        note("Loopback is the safe default. Local network mode listens on all local IPv4 interfaces; keep it behind your Mac firewall and rotate the token if another device has seen it.")

        section("Connect to another Cargo")
        tailscalePopup.addItem(withTitle: "Tailscale servers…")
        tailscalePopup.target = self
        tailscalePopup.action = #selector(tailscaleServerSelected)
        row("Auto-find", [tailscalePopup, findTailscaleButton])
        row("Resident address", serverURLField)
        note("Paste the resident's pairing link here and press Connect; it fills the address and token.")
        row("Client name", clientNameField)
        row("Token", [remoteTokenField, connectClientButton, disconnectClientButton])
        row("Status", clientStatusLabel)
        row("Clients", clientsLabel)
        note("This is the same Cargo app in client mode. The resident remains the source of truth and holds Put.io, Chill, metadata, subtitle, and library credentials. This device only needs the resident token and network access; use one resident and as many trusted client devices as needed.")
        row(nil, statusLabel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteSessionDidChange(_:)),
            name: CargoRemoteClientSession.didChange,
            object: coordinator.remoteClientSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remotePresenceDidChange(_:)),
            name: CargoRemotePresenceRegistry.didChange,
            object: coordinator.remotePresenceRegistry
        )
    }

    override func refresh() {
        let settings = coordinator.state.settings
        if let index = scopePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == settings.remoteNetworkScope.rawValue
        }) {
            scopePopup.selectItem(at: index)
        }
        endpointLabel.stringValue = settings.remoteNetworkScope == .localhost
            ? "http://127.0.0.1:\(CargoHTTPServer.Configuration.defaultPort)"
            : "http://<this Mac's local address>:\(CargoHTTPServer.Configuration.defaultPort)"
        tokenLabel.stringValue = coordinator.remoteAPITokenExists ? "Saved in Keychain" : "Not created yet"
        if !isEditing(serverURLField) {
            serverURLField.stringValue = settings.remoteServerURL
        }
        if !isEditing(clientNameField), clientNameField.stringValue.isEmpty {
            clientNameField.stringValue = coordinator.remoteClientSession.defaultClientName
        }
        if !isEditing(remoteTokenField) {
            remoteTokenField.stringValue = coordinator.remoteClientSession.isConnected || coordinator.remoteClientSession.status != "Not connected"
                ? "••••••••••••••••"
                : ""
        }
        clientStatusLabel.stringValue = coordinator.remoteClientSession.status
        disconnectClientButton.isEnabled = coordinator.remoteClientSession.isConnected

        let localPresence = coordinator.remotePresenceRegistry.snapshot()
        if let remotePresence = coordinator.remoteClientSession.presence {
            let names = remotePresence.clients.map(\.name).joined(separator: ", ")
            clientsLabel.stringValue = names.isEmpty
                ? "Connected to \(remotePresence.residentName); no clients listed"
                : "\(remotePresence.residentName): \(names)"
        } else if localPresence.clients.isEmpty {
            clientsLabel.stringValue = "No remote clients connected"
        } else {
            clientsLabel.stringValue = localPresence.clients.map(\.name).joined(separator: ", ")
        }
    }

    @objc private func scopeChanged() {
        guard let raw = scopePopup.selectedItem?.representedObject as? String,
              let scope = CargoRemoteNetworkScope(rawValue: raw) else { return }
        save { $0.remoteNetworkScope = scope }
    }

    @objc private func copyToken() {
        do {
            let token = try coordinator.ensureRemoteAPIToken()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(token, forType: .string)
            statusLabel.stringValue = "Token copied to the clipboard"
            refresh()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    /// Everything a client needs, in one string. Switches the resident to
    /// local-network scope when it is loopback-only, since a link nobody can
    /// reach is worse than none.
    @objc private func copyPairingLink() {
        copyPairingLinkButton.isEnabled = false
        statusLabel.stringValue = "Building pairing link…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { copyPairingLinkButton.isEnabled = true }
            do {
                let token = try coordinator.ensureRemoteAPIToken()
                var notes: [String] = []
                if coordinator.state.settings.remoteNetworkScope == .localhost {
                    try coordinator.updateSettings { $0.remoteNetworkScope = .localNetwork }
                    notes.append("Network set to Local network")
                }
                let host: String
                if let dnsName = await CargoTailscaleDiscovery.selfDNSName() {
                    host = dnsName
                } else {
                    host = ProcessInfo.processInfo.hostName
                    notes.append("no Tailscale, using \(host)")
                }
                let link = CargoPairingLink(
                    serverURL: "http://\(host):\(CargoHTTPServer.Configuration.defaultPort)",
                    token: token
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.urlString, forType: .string)
                statusLabel.stringValue = (["Pairing link copied · paste it into the other Cargo's Resident address"] + notes).joined(separator: " · ")
                refresh()
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    /// Fills the client fields from a pairing link and connects.
    func connect(with link: CargoPairingLink) {
        serverURLField.stringValue = link.serverURL
        remoteTokenField.stringValue = link.token
        connectClient()
    }

    @objc private func rotateToken() {
        let alert = NSAlert()
        alert.messageText = "Rotate remote-access token?"
        alert.informativeText = "Any remote client using the current token will stop working. Cargo will generate a new token and copy it to the clipboard."
        alert.addButton(withTitle: "Rotate and Copy")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let token = try coordinator.rotateRemoteAPIToken()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(token, forType: .string)
            statusLabel.stringValue = "New token copied to the clipboard"
            refresh()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func connectClient() {
        if let link = CargoPairingLink(parsing: serverURLField.stringValue) {
            serverURLField.stringValue = link.serverURL
            remoteTokenField.stringValue = link.token
        }
        let address = serverURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            statusLabel.stringValue = "Enter the resident Cargo address"
            return
        }

        do {
            try coordinator.updateSettings {
                $0.remoteClientEnabled = true
                $0.remoteServerURL = address
            }
        } catch {
            statusLabel.stringValue = error.localizedDescription
            return
        }

        let token = remoteTokenField.stringValue.hasPrefix("••") ? "" : remoteTokenField.stringValue
        let name = clientNameField.stringValue
        Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.remoteClientSession.connect(
                baseURLString: address,
                token: token,
                clientName: name
            )
            refresh()
        }
    }

    @objc private func disconnectClient() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.remoteClientSession.disconnect()
            try? coordinator.updateSettings { $0.remoteClientEnabled = false }
            refresh()
        }
    }

    @objc private func findTailscaleServers() {
        findTailscaleButton.isEnabled = false
        statusLabel.stringValue = "Looking for Cargo servers on Tailscale…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { findTailscaleButton.isEnabled = true }
            do {
                let servers = try await CargoTailscaleDiscovery().findServers()
                discoveredTailscaleServers = servers
                tailscalePopup.removeAllItems()
                if servers.isEmpty {
                    tailscalePopup.addItem(withTitle: "No Cargo servers found")
                    statusLabel.stringValue = "No reachable Cargo servers found on Tailscale"
                } else {
                    for server in servers {
                        tailscalePopup.addItem(withTitle: server.displayName)
                        tailscalePopup.lastItem?.representedObject = server.address
                    }
                    tailscalePopup.selectItem(at: 0)
                    serverURLField.stringValue = servers[0].address
                    statusLabel.stringValue = "Found \(servers.count) Cargo server\(servers.count == 1 ? "" : "s")"
                }
            } catch {
                tailscalePopup.removeAllItems()
                tailscalePopup.addItem(withTitle: "Tailscale unavailable")
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func tailscaleServerSelected() {
        guard let address = tailscalePopup.selectedItem?.representedObject as? String else { return }
        serverURLField.stringValue = address
    }

    @objc private func remoteSessionDidChange(_ notification: Notification) { refresh() }
    @objc private func remotePresenceDidChange(_ notification: Notification) { refresh() }
}

// MARK: - Chill

final class ChillPage: CargoPage, NSTextFieldDelegate {
    private let accountLabel = SettingsForm.caption("")
    private let tokenField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "Paste the token from chill.institute"
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return field
    }()
    private lazy var saveButton = SettingsForm.button("Save & Test", target: self, action: #selector(saveToken))
    private lazy var disconnectButton = SettingsForm.button("Disconnect", target: self, action: #selector(disconnect))

    override func build() {
        section("Account")
        row("Status", accountLabel)
        row("Token", [tokenField, saveButton, disconnectButton])
        row(nil, SettingsForm.button("Get a token…", target: self, action: #selector(openTokenPage)))
        note("Chill searches releases and hands the selected link to Put.io. The token is stored in Keychain; Cargo does not manage indexers or files on Chill.")
        row(nil, statusLabel)
        tokenField.delegate = self
    }

    override func refresh() {
        accountLabel.stringValue = coordinator.chillStatus
        disconnectButton.isHidden = !coordinator.isChillConnected
        if !isEditing(tokenField) {
            tokenField.stringValue = coordinator.chillStatus.contains("Token saved") || coordinator.isChillConnected
                ? "••••••••••••••••"
                : ""
        }
    }

    @objc private func openTokenPage() {
        NSWorkspace.shared.open(URL(string: "https://chill.institute/auth/cli-token")!)
    }

    @objc private func saveToken() {
        let value = tokenField.stringValue
        guard !value.hasPrefix("••") else {
            Task { await coordinator.verifyChillConnection() }
            return
        }
        do {
            try coordinator.saveChillToken(value)
            tokenField.stringValue = "••••••••••••••••"
            Task { await coordinator.verifyChillConnection() }
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func disconnect() {
        do {
            try coordinator.removeChillToken()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === tokenField else { return }
        saveToken()
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
        guard let editor = field.currentEditor() else { return false }
        return view.window?.firstResponder === editor
    }
}

// MARK: - Put.io

final class PutIOPage: CargoPage {
    private lazy var connectButton = SettingsForm.button("Connect with Put.io…", target: self, action: #selector(connect))
    private lazy var disconnectButton = SettingsForm.button("Disconnect", target: self, action: #selector(disconnect))
    private let accountLabel = SettingsForm.caption("")
    private let storageLabel = SettingsForm.label("")
    private let trashLabel = SettingsForm.label("")
    private lazy var emptyTrashButton = SettingsForm.button("Empty Trash…", target: self, action: #selector(emptyTrash))
    private let intervalPopup = SettingsForm.popup()
    private var emptyingTrash = false

    override func build() {
        section("Account")
        row("Status", accountLabel)
        row(nil, [connectButton, disconnectButton])
        note("Authorization happens in the browser and returns through cargo://oauth/callback. The token lives in Keychain, never in the state file or logs.")

        section("Storage")
        row("Disk", storageLabel)
        row("Trash", [trashLabel, emptyTrashButton])
        note("Files Cargo removes after a verified local copy skip the trash. Files you delete by hand go to the trash and still count against your quota until it is emptied.")

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
        if let disk = coordinator.diskUsage {
            storageLabel.stringValue = "\(Formatters.bytes(disk.usedBytes)) used · \(Formatters.bytes(disk.availableBytes)) free of \(Formatters.bytes(disk.totalBytes))"
        } else {
            storageLabel.stringValue = "—"
        }
        if let trash = coordinator.trashSummary {
            trashLabel.stringValue = trash.count == 0 ? "Empty" : "\(trash.count) item\(trash.count == 1 ? "" : "s") · \(Formatters.bytes(trash.bytes))"
            emptyTrashButton.isEnabled = trash.count > 0 && !emptyingTrash
        } else {
            trashLabel.stringValue = "—"
            emptyTrashButton.isEnabled = false
        }
    }

    @objc private func emptyTrash() {
        guard !emptyingTrash else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Put.io trash?"
        alert.informativeText = "Everything in the trash is deleted for good. This includes files you trashed outside Cargo."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        emptyingTrash = true
        emptyTrashButton.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.emptyingTrash = false
                self.refresh()
            }
            do {
                try await self.coordinator.emptyPutIOTrash()
            } catch {
                self.statusLabel.stringValue = error.localizedDescription
            }
        }
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
    private let tmdbKeyField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "v3 API key"
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return field
    }()
    private let tmdbStatusLabel = SettingsForm.caption("")
    private let omdbKeyField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "OMDb API key (optional)"
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return field
    }()
    private let omdbStatusLabel = SettingsForm.caption("")
    private let languagePopup = SettingsForm.popup()
    private let osUsernameField = SettingsForm.textField(placeholder: "username", width: 180)
    private let osAPIKeyField = SettingsForm.textField(placeholder: "API key", width: 300)
    private let osPasswordField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "password"
        field.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return field
    }()
    private let osStatusLabel = SettingsForm.caption("")

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

        section("TMDB")
        tmdbKeyField.delegate = self
        let getKey = SettingsForm.button("Get a key…", target: self, action: #selector(openTMDBSignup))
        row("API key", [tmdbKeyField, getKey])
        row(nil, [tmdbStatusLabel, SettingsForm.button("Retry Misses", target: self, action: #selector(retryMisses))])
        note("Posters, years and episode counts for the Library and Watchlist. Paste the v3 API key (32 hex characters), not the read access token. Free for personal use; the key lives in Keychain.")

        section("Additional ratings")
        omdbKeyField.delegate = self
        let getOMDBKey = SettingsForm.button("Get a key…", target: self, action: #selector(openOMDBSignup))
        row("OMDb API key", [omdbKeyField, getOMDBKey])
        row(nil, omdbStatusLabel)
        note("Optional. OMDb supplies IMDb, Rotten Tomatoes and Metacritic scores when a title has an IMDb id. The key is stored in Keychain.")

        section("Subtitles")
        for language in SubtitleLanguage.common {
            languagePopup.addItem(withTitle: language.name)
            languagePopup.lastItem?.representedObject = language.code
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        row("Language", languagePopup)
        osUsernameField.delegate = self
        osPasswordField.delegate = self
        osAPIKeyField.delegate = self
        row("OpenSubtitles", [osUsernameField, osPasswordField])
        let getOSKey = SettingsForm.button("Get a key…", target: self, action: #selector(openOpenSubtitles))
        row("API key", [osAPIKeyField, getOSKey])
        row(nil, osStatusLabel)
        note("After a file is organized, Cargo saves Put.io's subtitle for it when there is one, else asks OpenSubtitles (the EasySubs engine: hash match first, filename second). Free account + API consumer key; the password lives in Keychain.")
        row(nil, statusLabel)
    }

    @objc private func languageChanged() {
        guard let code = languagePopup.selectedItem?.representedObject as? String else { return }
        save { $0.subtitleLanguage = code }
    }

    @objc private func openOpenSubtitles() {
        NSWorkspace.shared.open(URL(string: "https://www.opensubtitles.com/en/consumers")!)
    }

    @objc private func retryMisses() {
        coordinator.retryMetadataMisses()
    }

    @objc private func openTMDBSignup() {
        NSWorkspace.shared.open(URL(string: "https://www.themoviedb.org/settings/api")!)
    }

    @objc private func openOMDBSignup() {
        NSWorkspace.shared.open(URL(string: "https://www.omdbapi.com/apikey.aspx")!)
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
        let hasKey = coordinator.hasTMDBKey
        if !isEditing(tmdbKeyField) { tmdbKeyField.stringValue = hasKey ? "••••••••••••••••" : "" }
        let enriched = coordinator.state.metadata.count
        let misses = coordinator.state.metadataMisses.count
        var status = hasKey ? "Key saved · \(enriched) matched" : "No key"
        if misses > 0 { status += " · \(misses) not found" }
        if let error = coordinator.tmdbStatus { status += " · \(error)" }
        tmdbStatusLabel.stringValue = status
        let hasOMDBKey = coordinator.hasOMDBKey
        if !isEditing(omdbKeyField) { omdbKeyField.stringValue = hasOMDBKey ? "••••••••••••••••" : "" }
        omdbStatusLabel.stringValue = hasOMDBKey ? "Key saved" : "No key · optional"
        if let index = languagePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == settings.subtitleLanguage }) {
            languagePopup.selectItem(at: index)
        }
        if !isEditing(osUsernameField) { osUsernameField.stringValue = settings.openSubtitlesUsername }
        if !isEditing(osAPIKeyField) { osAPIKeyField.stringValue = settings.openSubtitlesAPIKey }
        let hasPassword = !(coordinator.openSubtitlesCredentials.password.isEmpty)
        if !isEditing(osPasswordField) { osPasswordField.stringValue = hasPassword ? "••••••••" : "" }
        osStatusLabel.stringValue = coordinator.openSubtitlesCredentials.isComplete ? "Ready" : "Put.io subtitles only until username, password and API key are set"
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
        } else if field === osUsernameField {
            let value = osUsernameField.stringValue.trimmingCharacters(in: .whitespaces)
            save { $0.openSubtitlesUsername = value }
        } else if field === osAPIKeyField {
            let value = osAPIKeyField.stringValue.trimmingCharacters(in: .whitespaces)
            save { $0.openSubtitlesAPIKey = value }
        } else if field === osPasswordField {
            let value = osPasswordField.stringValue
            guard !value.hasPrefix("••") else { return }
            do {
                try coordinator.saveOpenSubtitlesPassword(value)
                statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        } else if field === tmdbKeyField {
            let value = tmdbKeyField.stringValue
            guard !value.hasPrefix("••") else { return }
            do {
                try coordinator.saveTMDBKey(value)
                statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
                Task { await coordinator.enrichMetadata() }
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        } else if field === omdbKeyField {
            let value = omdbKeyField.stringValue
            guard !value.hasPrefix("••") else { return }
            do {
                try coordinator.saveOMDBKey(value)
                statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
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
            ("Ask Put.io to unpack archives (rar releases)", \.automaticExtractEnabled),
            ("Organize and rename Inbox media", \.automaticOrganizationEnabled),
            ("Delete Put.io file after verified local copy", \.automaticRemoteCleanupEnabled),
            ("Remove Inbox sidecars and empty folders", \.automaticInboxCleanupEnabled),
            ("Clear finished transfers from Put.io after each cycle", \.automaticTransferCleanEnabled),
            ("Fetch subtitles after organizing", \.automaticSubtitlesEnabled)
        ]
        for (title, keyPath) in toggles {
            let control = toggle(title, isOn: coordinator.state.settings[keyPath: keyPath]) { [weak self] value in
                self?.save { $0[keyPath: keyPath] = value }
            }
            switches.append((control, keyPath))
        }
        note("Put.io deletion happens only after a verified local copy and skips the trash. Extracted archives are removed the same way. Inbox cleanup removes non-media sidecars only when a nested folder has no media or subfolders left.")

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
