import AppKit

/// Standalone Settings window (⌘,). Every control saves on change — no Save buttons.
@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let coordinator: CargoCoordinator

    private let connectButton = NSButton(title: "Connect with Put.io…", target: nil, action: nil)
    private let disconnectButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private let accountStatusLabel = Theme.label(style: .detail)
    private let watchlistURLField = NSTextField()
    private let watchlistStatusLabel = Theme.label(style: .detail)
    private let libraryPathLabel = Theme.label(style: .body, lineBreak: .byTruncatingMiddle)
    private let stagingField = NSTextField()
    private let moviesField = NSTextField()
    private let tvShowsField = NSTextField()
    private let refreshIntervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var switches: [(NSSwitch, WritableKeyPath<CargoSettings, Bool>)] = []
    private let statusLabel = Theme.label(style: .detail)

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cargo Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 0).width = 150
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .firstBaseline

        // Put.io
        addHeader(grid, "Put.io")
        connectButton.target = self
        connectButton.action = #selector(connect)
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnect)
        style(connectButton)
        style(disconnectButton)
        grid.addRow(with: [label("Account"), row([connectButton, disconnectButton, accountStatusLabel])])
        grid.addRow(with: [label("Check Put.io every"), row([refreshIntervalPopup])])
        refreshIntervalPopup.controlSize = .small
        refreshIntervalPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for minutes in CargoSettings.refreshIntervalChoices {
            refreshIntervalPopup.addItem(withTitle: minutes == 1 ? "1 minute" : "\(minutes) minutes")
            refreshIntervalPopup.lastItem?.tag = minutes
        }
        refreshIntervalPopup.target = self
        refreshIntervalPopup.action = #selector(refreshIntervalChanged)

        // Watchlist
        addHeader(grid, "IMDb Watchlist")
        configure(watchlistURLField, placeholder: "https://www.imdb.com/user/…/watchlist/")
        let refreshWatchlist = NSButton(title: "Refresh", target: self, action: #selector(refreshWatchlistNow))
        style(refreshWatchlist)
        grid.addRow(with: [label("Public list URL"), row([watchlistURLField, refreshWatchlist])])
        grid.addRow(with: [NSGridCell.emptyContentView, watchlistStatusLabel])

        // Library
        addHeader(grid, "Local library")
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseLibraryRoot))
        style(choose)
        libraryPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.addRow(with: [label("Library folder"), row([libraryPathLabel, choose])])
        for (title, field) in [("Staging folder", stagingField), ("Movies folder", moviesField), ("TV Shows folder", tvShowsField)] {
            configure(field, placeholder: nil)
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
            grid.addRow(with: [label(title), row([field])])
        }

        // Automation
        addHeader(grid, "Automation")
        let toggles: [(String, WritableKeyPath<CargoSettings, Bool>)] = [
            ("Sync new completed Put.io media", \.automaticSyncEnabled),
            ("Organize and rename Inbox media", \.automaticOrganizationEnabled),
            ("Delete Put.io file after verified local copy", \.automaticRemoteCleanupEnabled),
            ("Remove Inbox sidecars and empty folders", \.automaticInboxCleanupEnabled),
            ("Send notifications", \.notificationsEnabled),
            ("Launch Cargo at login", \.launchAtLoginEnabled)
        ]
        for (title, keyPath) in toggles {
            let toggle = NSSwitch()
            toggle.controlSize = .small
            toggle.target = self
            toggle.action = #selector(switchChanged(_:))
            switches.append((toggle, keyPath))
            grid.addRow(with: [row([toggle, Theme.label(title, style: .body)]), NSGridCell.emptyContentView])
            grid.row(at: grid.numberOfRows - 1).mergeCells(in: NSRange(location: 0, length: 2))
        }
        let note = Theme.label(
            "Put.io deletion happens only after a verified local copy. Inbox cleanup removes non-media sidecars only when a nested folder has no media or subfolders left.",
            style: .caption,
            wraps: true
        )
        note.preferredMaxLayoutWidth = 500
        grid.addRow(with: [note, NSGridCell.emptyContentView])
        grid.row(at: grid.numberOfRows - 1).mergeCells(in: NSRange(location: 0, length: 2))

        // Footer
        statusLabel.textColor = .tertiaryLabelColor
        let about = Theme.label("Cargo \(Theme.buildLabel)", style: .caption)
        let footer = NSStackView(views: [statusLabel, about])
        footer.orientation = .horizontal
        footer.distribution = .equalSpacing
        footer.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            footer.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            footer.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        return content
    }

    private func addHeader(_ grid: NSGridView, _ title: String) {
        let header = Theme.label(title, style: .sectionHeader)
        grid.addRow(with: [header, NSGridCell.emptyContentView])
        let row = grid.row(at: grid.numberOfRows - 1)
        row.mergeCells(in: NSRange(location: 0, length: 2))
        if grid.numberOfRows > 1 { row.topPadding = 14 }
    }

    private func label(_ text: String) -> NSTextField {
        Theme.label(text, style: .body, color: .secondaryLabelColor)
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func style(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    private func configure(_ field: NSTextField, placeholder: String?) {
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = placeholder
        field.delegate = self
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // MARK: - State

    @objc private func coordinatorDidChange() {
        refresh()
    }

    private func refresh() {
        let settings = coordinator.state.settings
        let connected = coordinator.isConnected
        connectButton.isHidden = connected
        disconnectButton.isHidden = !connected
        accountStatusLabel.stringValue = coordinator.putIOStatus
        refreshIntervalPopup.selectItem(withTag: settings.refreshIntervalMinutes)

        if window?.firstResponder !== watchlistURLField.currentEditor() {
            watchlistURLField.stringValue = settings.imdbWatchlistURL
        }
        watchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus

        libraryPathLabel.stringValue = settings.libraryRootPath ?? "No folder selected"
        libraryPathLabel.textColor = settings.hasLibraryRoot ? .labelColor : .systemOrange
        for (field, value) in [(stagingField, settings.stagingDirectoryName), (moviesField, settings.moviesDirectoryName), (tvShowsField, settings.tvShowsDirectoryName)]
        where window?.firstResponder !== field.currentEditor() {
            field.stringValue = value
        }
        for (toggle, keyPath) in switches {
            toggle.state = settings[keyPath: keyPath] ? .on : .off
        }
    }

    private func save(_ mutate: (inout CargoSettings) throws -> Void) {
        do {
            try coordinator.updateSettings(mutate)
            statusLabel.stringValue = "Saved \(Formatters.time.string(from: Date()))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
            refresh()
        }
    }

    // MARK: - Actions

    @objc private func connect() {
        do {
            let url = try coordinator.beginPutIOAuthorization()
            NSWorkspace.shared.open(url)
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

    @objc private func refreshIntervalChanged() {
        let minutes = refreshIntervalPopup.selectedTag()
        save { $0.refreshIntervalMinutes = minutes }
    }

    @objc private func refreshWatchlistNow() {
        commitWatchlistURL()
        Task { _ = await coordinator.refreshIMDbWatchlist() }
    }

    @objc private func chooseLibraryRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Library Root"
        panel.message = "Choose the folder on the SSD that Infuse reads."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try coordinator.saveLibraryRoot(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        guard let (_, keyPath) = switches.first(where: { $0.0 === sender }) else { return }
        save { $0[keyPath: keyPath] = sender.state == .on }
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
