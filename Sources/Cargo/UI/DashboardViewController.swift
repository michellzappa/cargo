import AppKit

final class DashboardViewController: NSViewController {
    private let coordinator: CargoCoordinator
    private let contentStack = NSStackView()
    private let putIOViewPicker = NSSegmentedControl()
    private var selectedPutIOView = 0
    private var settingsExpanded = false
    private var settingsContentView: NSView?
    private let settingsToggle = NSButton()
    private let connectionLabel = NSTextField(labelWithString: "")
    private let refreshedLabel = NSTextField(labelWithString: "")
    private let putIOSettingsStatusLabel = NSTextField(labelWithString: "")
    private let libraryRootLabel = NSTextField(labelWithString: "")
    private let stagingDirectoryField = NSTextField()
    private let moviesDirectoryField = NSTextField()
    private let tvShowsDirectoryField = NSTextField()
    private let directorySettingsStatusLabel = NSTextField(labelWithString: "")

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

    private func buildInterface() {
        settingsExpanded = !coordinator.state.settings.hasLibraryRoot || coordinator.putIOStatus == "Not connected yet"

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

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
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh(_:)))
        refreshButton.bezelStyle = .rounded

        let quitButton = NSButton(title: "Quit Cargo", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded

        let controls = NSStackView(views: [refreshButton, quitButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        root.addArrangedSubview(header)
        root.addArrangedSubview(Self.separator())
        putIOViewPicker.segmentCount = 2
        putIOViewPicker.setLabel("Transfers", forSegment: 0)
        putIOViewPicker.setLabel("Files", forSegment: 1)
        putIOViewPicker.trackingMode = .selectOne
        putIOViewPicker.selectedSegment = selectedPutIOView
        putIOViewPicker.target = self
        putIOViewPicker.action = #selector(selectPutIOView(_:))
        root.addArrangedSubview(putIOViewPicker)
        root.addArrangedSubview(contentStack)
        root.addArrangedSubview(Self.separator())
        root.addArrangedSubview(controls)

        root.addArrangedSubview(Self.separator())
        root.addArrangedSubview(settingsSection())

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
        settingsToggle.title = "Settings"
        settingsToggle.bezelStyle = .inline
        settingsToggle.alignment = .left
        settingsToggle.contentTintColor = .secondaryLabelColor
        settingsToggle.target = self
        settingsToggle.action = #selector(toggleSettings(_:))
        updateSettingsToggle()

        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(emptyLabel("Configure the live workflow."))

        let putIOTitle = NSTextField(labelWithString: "Put.io account")
        putIOTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        section.addArrangedSubview(putIOTitle)

        let connectButton = NSButton(
            title: "Connect with Put.io",
            target: self,
            action: #selector(connectWithPutIO(_:))
        )
        connectButton.bezelStyle = .rounded

        let appLabel = NSTextField(labelWithString: "Browser sign-in · OAuth app \(PutIOOAuth.clientID)")
        appLabel.textColor = .secondaryLabelColor
        appLabel.font = .systemFont(ofSize: 11)

        let oauthRow = NSStackView(views: [connectButton, appLabel])
        oauthRow.orientation = .horizontal
        oauthRow.alignment = .centerY
        oauthRow.spacing = 8
        section.addArrangedSubview(oauthRow)

        putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        putIOSettingsStatusLabel.textColor = .secondaryLabelColor
        putIOSettingsStatusLabel.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(putIOSettingsStatusLabel)
        section.addArrangedSubview(emptyLabel("OAuth callback: cargo://oauth/callback"))

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

        let workflow = NSTextField(labelWithString: "Workflow: Put.io queue → SSD staging → local library → EasySubs")
        workflow.textColor = .tertiaryLabelColor
        workflow.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(workflow)

        let about = NSTextField(labelWithString: "Cargo \(Self.buildLabel)")
        about.textColor = .tertiaryLabelColor
        about.font = .systemFont(ofSize: 11)
        section.addArrangedSubview(about)

        settingsContentView = section
        section.isHidden = !settingsExpanded

        let wrapper = NSStackView(views: [settingsToggle, section])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 8
        return wrapper
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

    private func render() {
        coordinator.refresh()
        let state = coordinator.state

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        connectionLabel.stringValue = coordinator.putIOStatus
        putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
        refreshedLabel.stringValue = "Updated \(Self.timeFormatter.string(from: state.lastUpdated))"

        if selectedPutIOView == 0 {
            let remoteHeader = sectionHeader("Put.io transfers · \(state.transfers.count)")
            contentStack.addArrangedSubview(remoteHeader)

            if state.transfers.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No active transfers"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(state.transfers.map(remoteRow), maxHeight: 210, rowHeight: 45)
                )
            }
        } else {
            contentStack.addArrangedSubview(remoteFilesHeader())
            if state.remoteFiles.isEmpty {
                contentStack.addArrangedSubview(emptyLabel("No files at this Put.io location"))
            } else {
                contentStack.addArrangedSubview(
                    boundedList(state.remoteFiles.map(remoteFileRow), maxHeight: 210, rowHeight: 70)
                )
            }
        }

        let activeLocalJobs = state.localJobs.filter(Self.isActiveLocalJob)
        contentStack.addArrangedSubview(sectionHeader("Local sync queue · \(activeLocalJobs.count)"))
        if activeLocalJobs.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("Nothing waiting for the SSD"))
        } else {
            contentStack.addArrangedSubview(
                boundedList(activeLocalJobs.map(localRow), maxHeight: 120, rowHeight: 52)
            )
        }

        let inboxJobs = state.localJobs
            .filter { $0.status == .needsReview }
            .sorted { $0.updatedAt > $1.updatedAt }
        contentStack.addArrangedSubview(sectionHeader("Local inbox · \(inboxJobs.count) awaiting organization"))
        if inboxJobs.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No downloaded files waiting for organization"))
        } else {
            contentStack.addArrangedSubview(
                boundedList(inboxJobs.map { inboxRow($0, state: state) }, maxHeight: 190, rowHeight: 82)
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

    private func updateSettingsToggle() {
        settingsToggle.image = NSImage(
            systemSymbolName: settingsExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: settingsExpanded ? "Hide settings" : "Show settings"
        )
        settingsToggle.image?.isTemplate = true
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func remoteFilesHeader() -> NSView {
        let title = sectionHeader("Files in Put.io · \(coordinator.remoteFolderName) · \(coordinator.state.remoteFiles.count)")
        guard coordinator.canGoBackRemoteFolder else { return title }

        let backButton = NSButton(title: "Back", target: self, action: #selector(backRemoteFolder(_:)))
        backButton.bezelStyle = .rounded
        backButton.controlSize = .small

        let row = NSStackView(views: [title, backButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func selectPutIOView(_ sender: NSSegmentedControl) {
        selectedPutIOView = sender.selectedSegment
        render()
    }

    @objc private func toggleSettings(_ sender: Any?) {
        settingsExpanded.toggle()
        settingsContentView?.isHidden = !settingsExpanded
        updateSettingsToggle()
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
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
        title.lineBreakMode = .byTruncatingTail

        let details = NSTextField(labelWithString: "\(transfer.status.displayName) · \(Self.percent(transfer.progress)) · \(Self.bytes(transfer.sizeBytes))")
        details.textColor = transfer.status == .failed ? .systemRed : .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [title, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 660).isActive = true
        return stack
    }

    private func localRow(_ job: LocalSyncJob) -> NSView {
        let title = NSTextField(labelWithString: job.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail

        let destination = job.destination ?? "Destination not chosen"
        let details = NSTextField(labelWithString: "\(job.status.displayName) · \(Self.percent(job.progress)) · \(destination)")
        details.textColor = job.status == .failed || job.status == .needsReview ? .systemOrange : .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)
        details.lineBreakMode = .byTruncatingTail

        var labels: [NSView] = [title, details]
        if let errorMessage = job.errorMessage {
            let errorLabel = NSTextField(labelWithString: errorMessage)
            errorLabel.textColor = .systemRed
            errorLabel.font = .systemFont(ofSize: 11)
            errorLabel.lineBreakMode = .byTruncatingTail
            labels.append(errorLabel)
        }

        let stack = NSStackView(views: labels)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 660).isActive = true
        return stack
    }

    private func inboxRow(_ job: LocalSyncJob, state: CargoState) -> NSView {
        let title = NSTextField(labelWithString: job.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail

        let fileExists = job.destination.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let inboxStatus = fileExists ? "Downloaded · awaiting organization" : "Missing from staging"
        let status = NSTextField(labelWithString: inboxStatus)
        status.textColor = fileExists ? .systemOrange : .systemRed
        status.font = .systemFont(ofSize: 11, weight: .medium)

        let preview = LibraryOrganizer.preview(for: job.name, settings: state.settings)
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
        destinationLabel.lineBreakMode = .byTruncatingMiddle

        let explanation = NSTextField(labelWithString: "Preview only · \(preview.explanation)")
        explanation.textColor = .tertiaryLabelColor
        explanation.font = .systemFont(ofSize: 10)
        explanation.lineBreakMode = .byTruncatingTail

        let organizeButton = NSButton(
            title: preview.relativePath == nil ? "Review manually" : "Organize",
            target: self,
            action: #selector(organizeInboxItem(_:))
        )
        organizeButton.bezelStyle = .rounded
        organizeButton.controlSize = .small
        organizeButton.identifier = NSUserInterfaceItemIdentifier(job.id.uuidString)
        organizeButton.isEnabled = fileExists && preview.relativePath != nil

        let stack = NSStackView(views: [title, status, destinationLabel, explanation, organizeButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 660).isActive = true
        return stack
    }

    private func remoteFileRow(_ file: RemoteFile) -> NSView {
        let title = NSTextField(labelWithString: file.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail

        let downloadStatus = localJob(for: file).map(Self.downloadStatus) ?? "Not downloaded"
        let details = NSTextField(labelWithString: "\(file.type.displayName) · \(Self.bytes(file.sizeBytes)) · \(downloadStatus)")
        details.textColor = .secondaryLabelColor
        details.font = .systemFont(ofSize: 11)

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
        copy.widthAnchor.constraint(equalToConstant: 660).isActive = true
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
            await coordinator.refreshFromPutIO()
            putIOSettingsStatusLabel.stringValue = coordinator.putIOStatus
            render()
        }
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
              let jobID = UUID(uuidString: identifier),
              let job = coordinator.state.localJobs.first(where: { $0.id == jobID }) else {
            return
        }

        let preview = LibraryOrganizer.preview(for: job.name, settings: coordinator.state.settings)
        guard let relativePath = preview.relativePath else { return }
        let destination = coordinator.state.settings.libraryRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(relativePath)
                .path
        } ?? relativePath

        let alert = NSAlert()
        alert.messageText = "Organize this file?"
        alert.informativeText = "Cargo will move \(job.name) from \(coordinator.state.settings.stagingDirectoryName) to:\n\(destination)"
        alert.addButton(withTitle: "Organize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try coordinator.organizeLocalJob(jobID: jobID)
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

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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
