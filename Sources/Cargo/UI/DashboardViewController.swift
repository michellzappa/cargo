import AppKit

final class DashboardViewController: NSViewController {
    private struct InboxEntry {
        let sourceURL: URL
        let job: LocalSyncJob?

        var name: String {
            job?.name ?? sourceURL.lastPathComponent
        }
    }

    private let coordinator: CargoCoordinator
    private let contentStack = NSStackView()
    private let putIOViewPicker = NSSegmentedControl()
    private var selectedPutIOView = 0
    private var lastOrganizationMessage: String?
    private var settingsView: NSView?
    private static let listWidth: CGFloat = 640
    private let connectionLabel = NSTextField(labelWithString: "")
    private let refreshedLabel = NSTextField(labelWithString: "")
    private let putIOSettingsStatusLabel = NSTextField(labelWithString: "")
    private let imdbWatchlistURLField = NSTextField()
    private let imdbWatchlistStatusLabel = NSTextField(labelWithString: "")
    private let connectButton = NSButton(
        title: "Connect with Put.io",
        target: nil,
        action: nil
    )
    private var oauthRow: NSStackView?
    private let libraryRootLabel = NSTextField(labelWithString: "")
    private let stagingDirectoryField = NSTextField()
    private let moviesDirectoryField = NSTextField()
    private let tvShowsDirectoryField = NSTextField()
    private let directorySettingsStatusLabel = NSTextField(labelWithString: "")
    private let automaticSyncToggle = NSButton(
        checkboxWithTitle: "Sync new completed Put.io media",
        target: nil,
        action: nil
    )
    private let automaticOrganizationToggle = NSButton(
        checkboxWithTitle: "Organize and rename Inbox media",
        target: nil,
        action: nil
    )
    private let notificationsToggle = NSButton(
        checkboxWithTitle: "Send Cargo notifications",
        target: nil,
        action: nil
    )
    private let launchAtLoginToggle = NSButton(
        checkboxWithTitle: "Launch Cargo at login",
        target: nil,
        action: nil
    )
    private let automaticRemoteCleanupToggle = NSButton(
        checkboxWithTitle: "Delete Put.io file after verified local copy",
        target: nil,
        action: nil
    )
    private let automaticInboxCleanupToggle = NSButton(
        checkboxWithTitle: "Remove Inbox sidecars and empty folders after organizing",
        target: nil,
        action: nil
    )
    private let workflowSettingsStatusLabel = NSTextField(labelWithString: "")

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        render()
    }

    func refreshView() {
        guard isViewLoaded else { return }
        render()
    }

    func showSettings() {
        selectedPutIOView = 5
        if isViewLoaded {
            putIOViewPicker.selectedSegment = selectedPutIOView
            render()
        }
    }

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.setContentHuggingPriority(.required, for: .vertical)

        let title = NSTextField(labelWithString: "Cargo")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Put.io → local library · \(Self.buildLabel)")
        subtitle.textColor = .secondaryLabelColor

        connectionLabel.stringValue = coordinator.putIOStatus
        connectionLabel.textColor = .tertiaryLabelColor
        connectionLabel.font = .systemFont(ofSize: 11)

        refreshedLabel.textColor = .tertiaryLabelColor
        refreshedLabel.font = .systemFont(ofSize: 11)

        let header = NSStackView(views: [title, subtitle, connectionLabel, refreshedLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh(_:)))
        refreshButton.bezelStyle = .rounded

        let headerRow = NSStackView(views: [header, refreshButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = 12
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)

        root.addArrangedSubview(headerRow)
        root.addArrangedSubview(Self.separator())
        putIOViewPicker.segmentCount = 6
        putIOViewPicker.setLabel("Transfers", forSegment: 0)
        putIOViewPicker.setLabel("Files", forSegment: 1)
        putIOViewPicker.setLabel("Inbox", forSegment: 2)
        putIOViewPicker.setLabel("Watchlist", forSegment: 3)
        putIOViewPicker.setLabel("History", forSegment: 4)
        putIOViewPicker.setLabel("Settings", forSegment: 5)
        putIOViewPicker.trackingMode = .selectOne
        putIOViewPicker.selectedSegment = selectedPutIOView
        putIOViewPicker.target = self
        putIOViewPicker.action = #selector(selectPutIOView(_:))
        root.addArrangedSubview(putIOViewPicker)
        root.addArrangedSubview(contentStack)

        settingsView = settingsSection()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        scrollView.documentView = container
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func settingsSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(sectionHeader("Settings"))
        section.addArrangedSubview(emptyLabel("Configure the live workflow."))

        let putIOTitle = NSTextField(labelWithString: "Put.io account")
        putIOTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        section.addArrangedSubview(putIOTitle)

        connectButton.bezelStyle = .rounded
        connectButton.target = self
        connectButton.action = #selector(connectWithPutIO(_:))

        let appLabel = NSTextField(labelWithString: "Browser sign-in · OAuth app \(PutIOOAuth.clientID)")
        appLabel.textColor = .secondaryLabelColor
        appLabel.font = .systemFont(ofSize: 11)

        let oauthRow = NSStackView(views: [connectButton, appLabel])
        oauthRow.orientation = .horizontal
        oauthRow.alignment = .centerY
        oauthRow.spacing = 8
        oauthRow.detachesHiddenViews = true
        self.oauthRow = oauthRow
        section.addArrangedSubview(oauthRow)

        putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        putIOSettingsStatusLabel.textColor = .secondaryLabelColor
        putIOSettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(putIOSettingsStatusLabel)
        section.addArrangedSubview(emptyLabel("OAuth callback: cargo://oauth/callback"))

        let watchlistTitle = NSTextField(labelWithString: "IMDb Watchlist")
        watchlistTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        section.addArrangedSubview(watchlistTitle)
        section.addArrangedSubview(emptyLabel("Cargo watches this public list and compares it with Put.io media."))

        imdbWatchlistURLField.stringValue = coordinator.state.settings.imdbWatchlistURL
        imdbWatchlistURLField.controlSize = .small
        imdbWatchlistURLField.widthAnchor.constraint(equalToConstant: 520).isActive = true
        imdbWatchlistURLField.lineBreakMode = .byTruncatingMiddle
        let saveWatchlistButton = NSButton(
            title: "Save & refresh",
            target: self,
            action: #selector(refreshIMDbWatchlist(_:))
        )
        saveWatchlistButton.bezelStyle = .rounded
        saveWatchlistButton.controlSize = .small
        let watchlistURLRow = NSStackView(views: [imdbWatchlistURLField, saveWatchlistButton])
        watchlistURLRow.orientation = .horizontal
        watchlistURLRow.alignment = .centerY
        watchlistURLRow.spacing = 8
        section.addArrangedSubview(watchlistURLRow)

        imdbWatchlistStatusLabel.textColor = .secondaryLabelColor
        imdbWatchlistStatusLabel.font = .systemFont(ofSize: 11)
        imdbWatchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus
        section.addArrangedSubview(imdbWatchlistStatusLabel)

        let libraryTitle = NSTextField(labelWithString: "Local library")
        libraryTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        section.addArrangedSubview(libraryTitle)

        let chooseButton = NSButton(
            title: coordinator.state.settings.hasLibraryRoot ? "Change folder…" : "Choose folder…",
            target: self,
            action: #selector(chooseLibraryRoot(_:))
        )
        chooseButton.bezelStyle = .rounded
        libraryRootLabel.stringValue = coordinator.state.settings.libraryRootPath ?? "No SSD folder selected"
        libraryRootLabel.textColor = coordinator.state.settings.hasLibraryRoot
            ? .secondaryLabelColor
            : .systemOrange
        libraryRootLabel.font = .systemFont(ofSize: 11)
        libraryRootLabel.lineBreakMode = .byTruncatingMiddle
        libraryRootLabel.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let folderRow = NSStackView(views: [chooseButton, libraryRootLabel])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = 10
        section.addArrangedSubview(folderRow)

        stagingDirectoryField.stringValue = coordinator.state.settings.stagingDirectoryName
        moviesDirectoryField.stringValue = coordinator.state.settings.moviesDirectoryName
        tvShowsDirectoryField.stringValue = coordinator.state.settings.tvShowsDirectoryName
        for field in [stagingDirectoryField, moviesDirectoryField, tvShowsDirectoryField] {
            field.controlSize = .small
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
        }

        section.addArrangedSubview(fieldRow("Staging folder", stagingDirectoryField))
        section.addArrangedSubview(fieldRow("Movies folder", moviesDirectoryField))
        section.addArrangedSubview(fieldRow("TV Shows folder", tvShowsDirectoryField))

        let saveDirectoriesButton = NSButton(
            title: "Save library folders",
            target: self,
            action: #selector(saveDirectorySettings(_:))
        )
        saveDirectoriesButton.bezelStyle = .rounded
        section.addArrangedSubview(saveDirectoriesButton)

        directorySettingsStatusLabel.textColor = .secondaryLabelColor
        directorySettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(directorySettingsStatusLabel)

        let automationTitle = NSTextField(labelWithString: "Automation")
        automationTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        section.addArrangedSubview(automationTitle)
        section.addArrangedSubview(emptyLabel("Checked steps run automatically in the background."))
        configureWorkflowToggle(automaticSyncToggle, tag: 0)
        configureWorkflowToggle(automaticOrganizationToggle, tag: 1)
        configureWorkflowToggle(notificationsToggle, tag: 2)
        configureWorkflowToggle(launchAtLoginToggle, tag: 3)
        configureWorkflowToggle(automaticRemoteCleanupToggle, tag: 4)
        configureWorkflowToggle(automaticInboxCleanupToggle, tag: 5)
        section.addArrangedSubview(automaticSyncToggle)
        section.addArrangedSubview(automaticOrganizationToggle)
        section.addArrangedSubview(notificationsToggle)
        section.addArrangedSubview(launchAtLoginToggle)
        section.addArrangedSubview(automaticRemoteCleanupToggle)
        section.addArrangedSubview(automaticInboxCleanupToggle)
        section.addArrangedSubview(emptyLabel("Put.io deletion happens only after a verified local copy. Inbox cleanup removes non-media sidecars only when a nested folder has no media or subfolders left."))
        workflowSettingsStatusLabel.textColor = .secondaryLabelColor
        workflowSettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(workflowSettingsStatusLabel)

        let workflow = NSTextField(labelWithString: "Workflow: Put.io queue → SSD staging → local library → EasySubs")
        workflow.textColor = .tertiaryLabelColor
        workflow.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(workflow)

        let about = NSTextField(labelWithString: "Cargo \(Self.buildLabel)")
        about.textColor = .tertiaryLabelColor
        about.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(about)

        return section
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.widthAnchor.constraint(equalToConstant: 105).isActive = true
        return label
    }

    private func fieldRow(_ title: String, _ field: NSTextField) -> NSView {
        let row = NSStackView(views: [fieldLabel(title), field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func configureWorkflowToggle(_ toggle: NSButton, tag: Int) {
        toggle.tag = tag
        toggle.target = self
        toggle.action = #selector(toggleWorkflowStep(_:))
    }

    private func updateWorkflowControls(with settings: CargoSettings) {
        automaticSyncToggle.state = settings.automaticSyncEnabled ? .on : .off
        automaticOrganizationToggle.state = settings.automaticOrganizationEnabled ? .on : .off
        notificationsToggle.state = settings.notificationsEnabled ? .on : .off
        launchAtLoginToggle.state = settings.launchAtLoginEnabled ? .on : .off
        automaticRemoteCleanupToggle.state = settings.automaticRemoteCleanupEnabled ? .on : .off
        automaticInboxCleanupToggle.state = settings.automaticInboxCleanupEnabled ? .on : .off
    }

    private func render() {
        coordinator.refresh()
        let state = coordinator.state

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        connectionLabel.stringValue = coordinator.putIOStatus
        putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        imdbWatchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus
        let isConnected = coordinator.putIOStatus.hasPrefix("Connected as ")
        connectButton.isHidden = isConnected
        refreshedLabel.stringValue = "Updated \(Self.timeFormatter.string(from: state.lastUpdated))"
        updateWorkflowControls(with: state.settings)
        let inboxCount = coordinator.inboxFileURLs().count
        putIOViewPicker.setLabel(inboxCount > 0 ? "Inbox \(inboxCount)" : "Inbox", forSegment: 2)
        let watchlistCount = state.imdbWatchlistItems.count
        putIOViewPicker.setLabel(watchlistCount > 0 ? "Watchlist \(watchlistCount)" : "Watchlist", forSegment: 3)

        switch selectedPutIOView {
        case 0:
            let remoteHeader = sectionHeader("Put.io transfers · \(state.transfers.count)")
            contentStack.addArrangedSubview(remoteHeader)

            if state.transfers.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No active transfers"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(state.transfers.map(remoteRow), maxHeight: 210, rowHeight: 45)
                )
            }
        case 1:
            contentStack.addArrangedSubview(sectionHeader("Put.io media · all folders · \(state.remoteMediaFiles.count)"))
            contentStack.addArrangedSubview(emptyLabel("Video files Cargo can sync, wherever they are in Put.io"))
            if state.remoteMediaFiles.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No video files found in Put.io"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(state.remoteMediaFiles.map(remoteFileRow), maxHeight: 300, rowHeight: 70)
                )
            }
        case 2:
            renderInbox(state)
        case 3:
            renderWatchlist(state)
        case 4:
            renderHistory(state)
        case 5:
            if let settingsView {
                contentStack.addArrangedSubview(settingsView)
            }
        default:
            break
        }
    }

    private func renderHistory(_ state: CargoState) {
        contentStack.addArrangedSubview(sectionHeader("History · \(state.history.count)"))
        if state.history.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No workflow activity yet"))
            return
        }

        contentStack.addArrangedSubview(
            boundedList(
                state.history.prefix(50).map(historyRow),
                maxHeight: 360,
                rowHeight: 52
            )
        )
    }

    private func renderWatchlist(_ state: CargoState) {
        contentStack.addArrangedSubview(sectionHeader("IMDb Watchlist · \(state.imdbWatchlistItems.count)"))
        contentStack.addArrangedSubview(emptyLabel(coordinator.imdbWatchlistStatus))

        if state.imdbWatchlistItems.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No Watchlist titles synced yet"))
            return
        }

        let counts = state.imdbWatchlistItems.reduce(into: [String: Int]()) { counts, item in
            let status = Self.watchlistStatus(for: item, state: state)
            counts[status, default: 0] += 1
        }
        let summary = [
            (counts["Organized"] ?? 0) > 0 ? "\(counts["Organized"]!) organized" : nil,
            (counts["Downloaded · in Inbox"] ?? 0) > 0 ? "\(counts["Downloaded · in Inbox"]!) in Inbox" : nil,
            (counts["Available in Put.io"] ?? 0) > 0 ? "\(counts["Available in Put.io"]!) available" : nil,
            (counts["Wanted"] ?? 0) > 0 ? "\(counts["Wanted"]!) wanted" : nil
        ].compactMap { $0 }.joined(separator: " · ")
        if !summary.isEmpty {
            contentStack.addArrangedSubview(emptyLabel(summary))
        }

        contentStack.addArrangedSubview(
            boundedList(state.imdbWatchlistItems.map { watchlistRow($0, state: state) }, maxHeight: 360, rowHeight: 56)
        )
    }

    private func watchlistRow(_ item: IMDbWatchlistItem, state: CargoState) -> NSView {
        let title = NSTextField(labelWithString: item.year.map { "\(item.title) (\($0))" } ?? item.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title, width: Self.listWidth - 90)

        let status = Self.watchlistStatus(for: item, state: state)
        let detail = NSTextField(labelWithString: "\(status) · \(item.id)")
        detail.textColor = Self.watchlistStatusColor(status)
        detail.font = .systemFont(ofSize: 11)
        clampedLabel(detail, width: Self.listWidth - 90)

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let searchButton = NSButton(
            title: "Search",
            target: self,
            action: #selector(searchWatchlistItem(_:))
        )
        searchButton.bezelStyle = .rounded
        searchButton.controlSize = .small
        searchButton.identifier = NSUserInterfaceItemIdentifier(item.title)

        let row = NSStackView(views: [textStack, searchButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return row
    }

    private static func watchlistStatus(for item: IMDbWatchlistItem, state: CargoState) -> String {
        let matchingJobs = state.localJobs.filter { job in
            watchlistNameMatches(item.title, filename: job.name)
        }
        if matchingJobs.contains(where: { $0.status == .completed }) {
            return "Organized"
        }
        if matchingJobs.contains(where: { $0.status == .needsReview }) {
            return "Downloaded · in Inbox"
        }
        if matchingJobs.contains(where: { $0.status == .queued || $0.status == .downloading || $0.status == .importing }) {
            return "Queued"
        }
        if state.remoteMediaFiles.contains(where: { watchlistNameMatches(item.title, filename: $0.displayPath) }) {
            return "Available in Put.io"
        }
        return "Wanted"
    }

    private static func watchlistNameMatches(_ title: String, filename: String) -> Bool {
        let normalizedTitle = normalizeWatchlistText(title)
        let normalizedFilename = normalizeWatchlistText(filename)
        return !normalizedTitle.isEmpty && normalizedFilename.contains(normalizedTitle)
    }

    private static func normalizeWatchlistText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func watchlistStatusColor(_ status: String) -> NSColor {
        switch status {
        case "Organized": .systemGreen
        case "Available in Put.io", "Queued", "Downloaded · in Inbox": .systemOrange
        default: .secondaryLabelColor
        }
    }

    private func renderInbox(_ state: CargoState) {
        if let lastOrganizationMessage {
            let notice = clampedLabel(emptyLabel(lastOrganizationMessage), mode: .byTruncatingMiddle)
            notice.textColor = .systemGreen
            contentStack.addArrangedSubview(notice)
        }

        let activeLocalJobs = state.localJobs.filter(Self.isActiveLocalJob)
        if !activeLocalJobs.isEmpty {
            contentStack.addArrangedSubview(
                sectionHeader("Downloading to \(state.settings.stagingDirectoryName) · \(activeLocalJobs.count)")
            )
            contentStack.addArrangedSubview(
                boundedList(activeLocalJobs.map(localRow), maxHeight: 120, rowHeight: 52)
            )
        }

        let pendingJobs = state.localJobs
            .filter { $0.status == .needsReview }
            .sorted { $0.updatedAt > $1.updatedAt }
        let jobsByDestination = pendingJobs.reduce(into: [String: LocalSyncJob]()) { jobs, job in
            if let destination = job.destination {
                jobs[destination] = job
            }
        }
        let inboxEntries = coordinator.inboxFileURLs().map { url in
            InboxEntry(sourceURL: url, job: jobsByDestination[url.path])
        }

        contentStack.addArrangedSubview(sectionHeader("Inbox · \(inboxEntries.count)"))
        contentStack.addArrangedSubview(emptyLabel("Files physically in \(state.settings.stagingDirectoryName)"))
        if inboxEntries.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("Nothing waiting for organization"))
        } else {
            contentStack.addArrangedSubview(
                boundedList(inboxEntries.map { inboxRow($0, state: state) }, maxHeight: 320, rowHeight: 88)
            )
        }

        let recentlyOrganized = state.localJobs
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
        if !recentlyOrganized.isEmpty {
            contentStack.addArrangedSubview(sectionHeader("Recently organized"))
            contentStack.addArrangedSubview(
                boundedList(recentlyOrganized.map(organizedRow), maxHeight: 170, rowHeight: 44)
            )
        }
    }

    private static func isActiveLocalJob(_ job: LocalSyncJob) -> Bool {
        switch job.status {
        case .queued, .downloading, .importing, .failed:
            true
        case .completed, .needsReview:
            false
        }
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    @objc private func selectPutIOView(_ sender: NSSegmentedControl) {
        selectedPutIOView = sender.selectedSegment
        render()
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    @discardableResult
    private func clampedLabel(
        _ label: NSTextField,
        mode: NSLineBreakMode = .byTruncatingTail,
        width: CGFloat = 640
    ) -> NSTextField {
        label.lineBreakMode = mode
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func boundedList(_ rows: [NSView], maxHeight: CGFloat, rowHeight: CGFloat) -> NSScrollView {
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 7
        list.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        list.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .bezelBorder
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        let contentHeight = min(maxHeight, max(38, CGFloat(rows.count) * rowHeight + 8))
        scrollView.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true

        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        return scrollView
    }

    private func remoteRow(_ transfer: RemoteTransfer) -> NSView {
        let title = NSTextField(labelWithString: transfer.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let details = NSTextField(labelWithString: "\(transfer.status.displayName) · \(Self.percent(transfer.progress)) · \(Self.bytes(transfer.sizeBytes))")
        details.textColor = transfer.status == .failed ? .systemRed : .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)
        clampedLabel(details)

        let stack = NSStackView(views: [title, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return stack
    }

    private func localRow(_ job: LocalSyncJob) -> NSView {
        let title = NSTextField(labelWithString: job.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let destination = job.destination ?? "Destination not chosen"
        let details = NSTextField(labelWithString: "\(job.status.displayName) · \(Self.percent(job.progress)) · \(destination)")
        details.textColor = job.status == .failed || job.status == .needsReview ? .systemOrange : .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)
        clampedLabel(details)

        var labels: [NSView] = [title, details]
        if let errorMessage = job.errorMessage {
            let errorLabel = NSTextField(labelWithString: errorMessage)
            errorLabel.textColor = .systemRed
            errorLabel.font = .systemFont(ofSize: 11)
            clampedLabel(errorLabel)
            labels.append(errorLabel)
        }

        let stack = NSStackView(views: labels)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return stack
    }

    private func inboxRow(_ entry: InboxEntry, state: CargoState) -> NSView {
        let title = NSTextField(labelWithString: entry.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let fileExists = FileManager.default.fileExists(atPath: entry.sourceURL.path)
        let inboxStatus = entry.job == nil
            ? "In inbox · not tracked by Cargo"
            : (fileExists ? "Downloaded · awaiting organization" : "Missing from staging")
        let status = NSTextField(labelWithString: inboxStatus)
        status.textColor = fileExists ? .systemOrange : .systemRed
        status.font = .systemFont(ofSize: 11, weight: .medium)
        clampedLabel(status)

        let preview = LibraryOrganizer.preview(for: entry.name, settings: state.settings)
        let destination = preview.relativePath.map { relativePath in
            if let rootPath = state.settings.libraryRootPath {
                return URL(fileURLWithPath: rootPath, isDirectory: true)
                    .appendingPathComponent(relativePath)
                    .path
            }
            return relativePath
        } ?? "Review manually"
        let destinationLabel = NSTextField(labelWithString: "Proposed \(preview.kind.displayName.lowercased()) destination: \(destination)")
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.font = .systemFont(ofSize: 11)
        clampedLabel(destinationLabel, mode: .byTruncatingMiddle)

        let explanation = NSTextField(labelWithString: "Preview only · \(preview.explanation)")
        explanation.textColor = .tertiaryLabelColor
        explanation.font = .systemFont(ofSize: 10)
        clampedLabel(explanation)

        let organizeButton = NSButton(
            title: preview.relativePath == nil ? "Review manually" : "Organize",
            target: self,
            action: #selector(organizeInboxItem(_:))
        )
        organizeButton.bezelStyle = .rounded
        organizeButton.controlSize = .small
        organizeButton.identifier = NSUserInterfaceItemIdentifier(entry.sourceURL.path)
        organizeButton.isEnabled = fileExists && preview.relativePath != nil

        let stack = NSStackView(views: [title, status, destinationLabel, explanation, organizeButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return stack
    }

    private func organizedRow(_ job: LocalSyncJob) -> NSView {
        let title = NSTextField(labelWithString: job.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let destination = NSTextField(labelWithString: "Organized → \(job.destination ?? "Destination unavailable")")
        destination.textColor = .systemGreen
        destination.font = .systemFont(ofSize: 11)
        clampedLabel(destination, mode: .byTruncatingMiddle)

        let stack = NSStackView(views: [title, destination])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return stack
    }

    private func historyRow(_ entry: CargoHistoryEntry) -> NSView {
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = Self.historyColor(for: entry.kind)
        clampedLabel(title)

        let detail = NSTextField(
            labelWithString: "\(Self.historyTimeFormatter.string(from: entry.date)) · \(entry.detail)"
        )
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        clampedLabel(detail, mode: .byTruncatingMiddle)

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return stack
    }

    private func remoteFileRow(_ file: RemoteFile) -> NSView {
        let title = NSTextField(labelWithString: file.displayPath)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let downloadStatus: String
        if coordinator.state.deletedRemoteFileIDs.contains(file.id) {
            downloadStatus = "Downloaded · Put.io copy deleted"
        } else {
            downloadStatus = localJob(for: file).map(Self.downloadStatus) ?? "Not downloaded"
        }
        let details = NSTextField(labelWithString: "\(file.type.displayName) · \(Self.bytes(file.sizeBytes)) · \(downloadStatus)")
        details.textColor = .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)
        clampedLabel(details)

        let copy = NSStackView(views: [title, details])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if file.isFolder {
            let openButton = NSButton(title: "Open", target: self, action: #selector(openRemoteFolder(_:)))
            openButton.bezelStyle = .rounded
            openButton.controlSize = .small
            openButton.tag = file.id
            copy.addArrangedSubview(openButton)
        } else {
            let job = localJob(for: file)
            let syncButton = NSButton(
                title: job.map(Self.syncButtonTitle) ?? "Sync",
                target: self,
                action: #selector(syncFile(_:))
            )
            syncButton.bezelStyle = .rounded
            syncButton.tag = file.id
            syncButton.isEnabled = job == nil
            copy.addArrangedSubview(syncButton)
        }

        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        return copy
    }

    private func localJob(for file: RemoteFile) -> LocalSyncJob? {
        coordinator.state.localJobs
            .filter { $0.remoteFileID == file.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private static func downloadStatus(_ job: LocalSyncJob) -> String {
        switch job.status {
        case .needsReview:
            "Downloaded · in inbox · awaiting organization"
        case .completed:
            "Downloaded"
        default:
            job.status.displayName
        }
    }

    private static func syncButtonTitle(_ job: LocalSyncJob) -> String {
        switch job.status {
        case .needsReview, .completed:
            "Downloaded"
        default:
            job.status.displayName
        }
    }

    @objc private func refresh(_ sender: Any?) {
        Task { @MainActor in
            _ = await coordinator.runBackgroundCycle()
            putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
            render()
        }
    }

    @objc private func refreshIMDbWatchlist(_ sender: Any?) {
        do {
            try coordinator.saveIMDbWatchlistURL(imdbWatchlistURLField.stringValue)
        } catch {
            imdbWatchlistStatusLabel.stringValue = error.localizedDescription
            return
        }

        imdbWatchlistStatusLabel.stringValue = "Loading IMDb Watchlist…"
        Task { @MainActor in
            _ = await coordinator.refreshIMDbWatchlist()
            imdbWatchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus
            render()
        }
    }

    @objc private func searchWatchlistItem(_ sender: NSButton) {
        guard let query = sender.identifier?.rawValue,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: "https://chill.institute/search") else {
            return
        }

        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func connectWithPutIO(_ sender: Any?) {
        do {
            let url = try coordinator.beginPutIOAuthorization()
            guard NSWorkspace.shared.open(url) else {
                throw PutIOOAuth.OAuthError.invalidCallback
            }
            putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        } catch {
            putIOSettingsStatusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func chooseLibraryRoot(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Library Root"
        panel.message = "Choose the folder on the SSD that Infuse reads."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try coordinator.saveLibraryRoot(url)
            libraryRootLabel.stringValue = url.path
            libraryRootLabel.textColor = .secondaryLabelColor
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func saveDirectorySettings(_ sender: Any?) {
        do {
            try coordinator.saveDirectorySettings(
                staging: stagingDirectoryField.stringValue,
                movies: moviesDirectoryField.stringValue,
                tvShows: tvShowsDirectoryField.stringValue
            )
            directorySettingsStatusLabel.stringValue = "Saved"
        } catch {
            directorySettingsStatusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func toggleWorkflowStep(_ sender: NSButton) {
        var settings = coordinator.state.settings
        let enabled = sender.state == .on
        switch sender.tag {
        case 0:
            settings.automaticSyncEnabled = enabled
        case 1:
            settings.automaticOrganizationEnabled = enabled
        case 2:
            settings.notificationsEnabled = enabled
        case 3:
            settings.launchAtLoginEnabled = enabled
        case 4:
            settings.automaticRemoteCleanupEnabled = enabled
        case 5:
            settings.automaticInboxCleanupEnabled = enabled
        default:
            return
        }

        do {
            try coordinator.saveWorkflowSettings(
                automaticSync: settings.automaticSyncEnabled,
                automaticOrganization: settings.automaticOrganizationEnabled,
                notifications: settings.notificationsEnabled,
                launchAtLogin: settings.launchAtLoginEnabled,
                automaticRemoteCleanup: settings.automaticRemoteCleanupEnabled,
                automaticInboxCleanup: settings.automaticInboxCleanupEnabled
            )
            workflowSettingsStatusLabel.stringValue = "Saved"
        } catch {
            workflowSettingsStatusLabel.stringValue = error.localizedDescription
            updateWorkflowControls(with: coordinator.state.settings)
        }
        render()
    }

    @objc private func syncFile(_ sender: NSButton) {
        let remoteFileID = sender.tag
        coordinator.enqueueLocalSync(remoteFileID: remoteFileID)
        render()

        Task { @MainActor in
            await coordinator.processLocalSync(remoteFileID: remoteFileID)
            render()
        }
    }

    @objc private func organizeInboxItem(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              !identifier.isEmpty else {
            return
        }

        let sourceURL = URL(fileURLWithPath: identifier)
        let job = coordinator.state.localJobs.first {
            $0.status == .needsReview && $0.destination == sourceURL.path
        }
        let itemName = job?.name ?? sourceURL.lastPathComponent

        let preview = LibraryOrganizer.preview(for: itemName, settings: coordinator.state.settings)
        guard let relativePath = preview.relativePath else { return }
        let destination = coordinator.state.settings.libraryRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(relativePath)
                .path
        } ?? relativePath

        do {
            if let job {
                try coordinator.organizeLocalJob(jobID: job.id)
            } else {
                try coordinator.organizeInboxFile(at: sourceURL)
            }
            lastOrganizationMessage = "Organized \(itemName) → \(destination)"
            render()
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    @objc private func openRemoteFolder(_ sender: NSButton) {
        let remoteFolderID = sender.tag
        Task { @MainActor in
            await coordinator.openRemoteFolder(remoteFolderID: remoteFolderID)
            render()
        }
    }

    @objc private func backRemoteFolder(_ sender: NSButton) {
        Task { @MainActor in
            await coordinator.goBackRemoteFolder()
            render()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let historyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func historyColor(for kind: CargoHistoryKind) -> NSColor {
        switch kind {
        case .info:
            .labelColor
        case .success:
            .systemGreen
        case .warning:
            .systemOrange
        case .failure:
            .systemRed
        }
    }

    private static var buildLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version, let build, !version.isEmpty, !build.isEmpty else { return "development build" }
        return "v\(version) (\(build))"
    }

    private static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    private static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
