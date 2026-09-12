import AppKit

final class DashboardViewController: NSViewController {
    private enum Layout {
        static let pageInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        static let pageSpacing: CGFloat = 16
        static let headerSpacing: CGFloat = 4
        static let sectionSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 4
        static let controlSpacing: CGFloat = 8
        static let listWidth: CGFloat = 640
        static let standardListHeight: CGFloat = 360
        static let compactListHeight: CGFloat = 220
        static let standardRowHeight: CGFloat = 56
        static let compactRowHeight: CGFloat = 48
        static let detailRowHeight: CGFloat = 88
        static let formLabelWidth: CGFloat = 120
        static let formFieldWidth: CGFloat = 280
        static let urlFieldWidth: CGFloat = 520
        static let libraryPathWidth: CGFloat = 480
    }

    private struct InboxEntry {
        let sourceURL: URL
        let job: LocalSyncJob?

        var name: String {
            job?.name ?? sourceURL.lastPathComponent
        }
    }

    private let coordinator: CargoCoordinator
    private let contentStack = NSStackView()
    private var selectedPutIOView = 0
    private var lastOrganizationMessage: String?
    private var settingsView: NSView?
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
            render()
        }
    }

    func selectView(_ index: Int) {
        guard (0..<6).contains(index) else { return }
        selectedPutIOView = index
        if isViewLoaded {
            render()
        }
    }

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = Layout.pageSpacing
        root.edgeInsets = Layout.pageInsets
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
        header.spacing = Layout.headerSpacing

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Layout.sectionSpacing
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh(_:)))
        styleButton(refreshButton)

        let headerRow = NSStackView(views: [header, refreshButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = Layout.controlSpacing
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)

        root.addArrangedSubview(headerRow)
        root.addArrangedSubview(Self.separator())
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
        section.spacing = Layout.sectionSpacing
        section.widthAnchor.constraint(equalToConstant: Layout.listWidth).isActive = true

        section.addArrangedSubview(sectionHeader("Settings"))
        section.addArrangedSubview(emptyLabel("Configure the live workflow."))

        section.addArrangedSubview(sectionHeader("Put.io account"))

        styleButton(connectButton)
        connectButton.target = self
        connectButton.action = #selector(connectWithPutIO(_:))

        let appLabel = NSTextField(labelWithString: "Browser sign-in · OAuth app \(PutIOOAuth.clientID)")
        appLabel.textColor = .secondaryLabelColor
        appLabel.font = .systemFont(ofSize: 11)

        let oauthRow = horizontalRow([connectButton, appLabel])
        oauthRow.detachesHiddenViews = true
        self.oauthRow = oauthRow
        section.addArrangedSubview(oauthRow)

        putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        putIOSettingsStatusLabel.textColor = .secondaryLabelColor
        putIOSettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(putIOSettingsStatusLabel)
        section.addArrangedSubview(emptyLabel("OAuth callback: cargo://oauth/callback"))

        section.addArrangedSubview(sectionHeader("IMDb Watchlist"))
        section.addArrangedSubview(emptyLabel("Cargo watches this public list and compares it with Put.io media."))

        imdbWatchlistURLField.stringValue = coordinator.state.settings.imdbWatchlistURL
        styleField(imdbWatchlistURLField, width: Layout.urlFieldWidth)
        imdbWatchlistURLField.lineBreakMode = .byTruncatingMiddle
        let saveWatchlistButton = NSButton(
            title: "Save & refresh",
            target: self,
            action: #selector(refreshIMDbWatchlist(_:))
        )
        styleButton(saveWatchlistButton)
        let watchlistURLRow = horizontalRow([imdbWatchlistURLField, saveWatchlistButton])
        section.addArrangedSubview(watchlistURLRow)

        imdbWatchlistStatusLabel.textColor = .secondaryLabelColor
        imdbWatchlistStatusLabel.font = .systemFont(ofSize: 11)
        imdbWatchlistStatusLabel.stringValue = coordinator.imdbWatchlistStatus
        section.addArrangedSubview(imdbWatchlistStatusLabel)

        section.addArrangedSubview(sectionHeader("Local library"))

        let chooseButton = NSButton(
            title: coordinator.state.settings.hasLibraryRoot ? "Change folder…" : "Choose folder…",
            target: self,
            action: #selector(chooseLibraryRoot(_:))
        )
        styleButton(chooseButton)
        libraryRootLabel.stringValue = coordinator.state.settings.libraryRootPath ?? "No SSD folder selected"
        libraryRootLabel.textColor = coordinator.state.settings.hasLibraryRoot
            ? .secondaryLabelColor
            : .systemOrange
        libraryRootLabel.font = .systemFont(ofSize: 11)
        libraryRootLabel.lineBreakMode = .byTruncatingMiddle
        libraryRootLabel.widthAnchor.constraint(equalToConstant: Layout.libraryPathWidth).isActive = true

        let folderRow = horizontalRow([chooseButton, libraryRootLabel])
        section.addArrangedSubview(folderRow)

        stagingDirectoryField.stringValue = coordinator.state.settings.stagingDirectoryName
        moviesDirectoryField.stringValue = coordinator.state.settings.moviesDirectoryName
        tvShowsDirectoryField.stringValue = coordinator.state.settings.tvShowsDirectoryName
        for field in [stagingDirectoryField, moviesDirectoryField, tvShowsDirectoryField] {
            styleField(field, width: Layout.formFieldWidth)
        }

        section.addArrangedSubview(fieldRow("Staging folder", stagingDirectoryField))
        section.addArrangedSubview(fieldRow("Movies folder", moviesDirectoryField))
        section.addArrangedSubview(fieldRow("TV Shows folder", tvShowsDirectoryField))

        let saveDirectoriesButton = NSButton(
            title: "Save library folders",
            target: self,
            action: #selector(saveDirectorySettings(_:))
        )
        styleButton(saveDirectoriesButton)
        section.addArrangedSubview(saveDirectoriesButton)

        directorySettingsStatusLabel.textColor = .secondaryLabelColor
        directorySettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(directorySettingsStatusLabel)

        section.addArrangedSubview(sectionHeader("Automation"))
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
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: Layout.formLabelWidth).isActive = true
        return label
    }

    private func fieldRow(_ title: String, _ field: NSTextField) -> NSView {
        horizontalRow([fieldLabel(title), field])
    }

    private func styleButton(_ button: NSButton, small: Bool = true) {
        button.bezelStyle = .rounded
        button.controlSize = small ? .small : .regular
    }

    private func styleField(_ field: NSTextField, width: CGFloat) {
        field.controlSize = .small
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func verticalRow(
        _ views: [NSView],
        spacing: CGFloat = Layout.rowSpacing,
        width: CGFloat = Layout.listWidth
    ) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    private func horizontalRow(
        _ views: [NSView],
        spacing: CGFloat = Layout.controlSpacing
    ) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Layout.listWidth).isActive = true
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

    private func addSection(_ title: String, description: String? = nil) {
        contentStack.addArrangedSubview(sectionHeader(title))
        if let description {
            contentStack.addArrangedSubview(emptyLabel(description))
        }
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

        switch selectedPutIOView {
        case 0:
            addSection("Put.io transfers · \(state.transfers.count)")

            if state.transfers.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No active transfers"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(
                        state.transfers.map(remoteRow),
                        maxHeight: Layout.compactListHeight,
                        rowHeight: Layout.compactRowHeight
                    )
                )
            }
        case 1:
            addSection(
                "Put.io media · all folders · \(state.remoteMediaFiles.count)",
                description: "Video files Cargo can sync, wherever they are in Put.io"
            )
            if state.remoteMediaFiles.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No video files found in Put.io"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(
                        state.remoteMediaFiles.map(remoteFileRow),
                        maxHeight: Layout.standardListHeight,
                        rowHeight: Layout.detailRowHeight
                    )
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
        addSection("History · \(state.history.count)")
        if state.history.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No workflow activity yet"))
            return
        }

        contentStack.addArrangedSubview(
            boundedList(
                state.history.prefix(50).map(historyRow),
                maxHeight: Layout.standardListHeight,
                rowHeight: Layout.standardRowHeight
            )
        )
    }

    private func renderWatchlist(_ state: CargoState) {
        addSection(
            "IMDb Watchlist · \(state.imdbWatchlistItems.count)",
            description: coordinator.imdbWatchlistStatus
        )

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
            boundedList(
                state.imdbWatchlistItems.map { watchlistRow($0, state: state) },
                maxHeight: Layout.standardListHeight,
                rowHeight: Layout.standardRowHeight
            )
        )
    }

    private func watchlistRow(_ item: IMDbWatchlistItem, state: CargoState) -> NSView {
        let title = NSTextField(labelWithString: item.year.map { "\(item.title) (\($0))" } ?? item.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title, width: Layout.listWidth - 90)

        let status = Self.watchlistStatus(for: item, state: state)
        let addedLabel = item.addedAt.map {
            "Added \(Self.watchlistDateFormatter.string(from: $0))"
        } ?? item.id
        let detail = NSTextField(labelWithString: "\(status) · \(addedLabel)")
        detail.textColor = Self.watchlistStatusColor(status)
        detail.font = .systemFont(ofSize: 11)
        clampedLabel(detail, width: Layout.listWidth - 90)

        let textStack = verticalRow([title, detail], width: Layout.listWidth - 90)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let searchButton = NSButton(
            title: "Search",
            target: self,
            action: #selector(searchWatchlistItem(_:))
        )
        styleButton(searchButton)
        searchButton.identifier = NSUserInterfaceItemIdentifier(item.title)

        return horizontalRow([textStack, searchButton])
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
            addSection("Downloading to \(state.settings.stagingDirectoryName) · \(activeLocalJobs.count)")
            contentStack.addArrangedSubview(
                boundedList(
                    activeLocalJobs.map(localRow),
                    maxHeight: Layout.compactListHeight,
                    rowHeight: Layout.standardRowHeight
                )
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

        addSection(
            "Inbox · \(inboxEntries.count)",
            description: "Files physically in \(state.settings.stagingDirectoryName)"
        )
        if inboxEntries.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("Nothing waiting for organization"))
        } else {
            contentStack.addArrangedSubview(
                boundedList(
                    inboxEntries.map { inboxRow($0, state: state) },
                    maxHeight: Layout.standardListHeight,
                    rowHeight: Layout.detailRowHeight
                )
            )
        }

        let recentlyOrganized = state.localJobs
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
        if !recentlyOrganized.isEmpty {
            addSection("Recently organized")
            contentStack.addArrangedSubview(
                boundedList(
                    recentlyOrganized.map(organizedRow),
                    maxHeight: Layout.compactListHeight,
                    rowHeight: Layout.compactRowHeight
                )
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
        label.textColor = .labelColor
        return label
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        return label
    }

    @discardableResult
    private func clampedLabel(
        _ label: NSTextField,
        mode: NSLineBreakMode = .byTruncatingTail,
        width: CGFloat = Layout.listWidth
    ) -> NSTextField {
        label.lineBreakMode = mode
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func boundedList(
        _ rows: [NSView],
        maxHeight: CGFloat = Layout.standardListHeight,
        rowHeight: CGFloat = Layout.standardRowHeight
    ) -> NSScrollView {
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = Layout.rowSpacing
        list.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        list.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        scrollView.clipsToBounds = true
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: Layout.listWidth).isActive = true
        let spacingHeight = max(0, CGFloat(rows.count - 1)) * Layout.rowSpacing
        let naturalHeight = CGFloat(rows.count) * rowHeight + spacingHeight + 12
        let contentHeight = min(maxHeight, max(44, naturalHeight))
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

        return verticalRow([title, details])
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

        return verticalRow(labels)
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
        styleButton(organizeButton)
        organizeButton.identifier = NSUserInterfaceItemIdentifier(entry.sourceURL.path)
        organizeButton.isEnabled = fileExists && preview.relativePath != nil

        return verticalRow([title, status, destinationLabel, explanation, organizeButton])
    }

    private func organizedRow(_ job: LocalSyncJob) -> NSView {
        let title = NSTextField(labelWithString: job.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        clampedLabel(title)

        let destination = NSTextField(labelWithString: "Organized → \(job.destination ?? "Destination unavailable")")
        destination.textColor = .systemGreen
        destination.font = .systemFont(ofSize: 11)
        clampedLabel(destination, mode: .byTruncatingMiddle)

        return verticalRow([title, destination])
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

        return verticalRow([title, detail])
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

        let copy = verticalRow([title, details])
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if file.isFolder {
            let openButton = NSButton(title: "Open", target: self, action: #selector(openRemoteFolder(_:)))
            styleButton(openButton)
            openButton.tag = file.id
            copy.addArrangedSubview(openButton)
        } else {
            let job = localJob(for: file)
            let syncButton = NSButton(
                title: job.map(Self.syncButtonTitle) ?? "Sync",
                target: self,
                action: #selector(syncFile(_:))
            )
            styleButton(syncButton)
            syncButton.tag = file.id
            syncButton.isEnabled = job == nil
            copy.addArrangedSubview(syncButton)
        }

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

    private static let watchlistDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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
