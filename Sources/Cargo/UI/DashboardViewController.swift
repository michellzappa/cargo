import AppKit

final class DashboardViewController: NSViewController {
    private let coordinator: CargoCoordinator
    private let onSettings: () -> Void
    private let contentStack = NSStackView()
    private let connectionLabel = NSTextField(labelWithString: "")
    private let refreshedLabel = NSTextField(labelWithString: "")

    init(coordinator: CargoCoordinator, onSettings: @escaping () -> Void = {}) {
        self.coordinator = coordinator
        self.onSettings = onSettings
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
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
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

        let settingsButton = NSButton(title: "Settings…", target: self, action: #selector(settings(_:)))
        settingsButton.bezelStyle = .rounded

        let quitButton = NSButton(title: "Quit Cargo", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded

        let controls = NSStackView(views: [refreshButton, settingsButton, quitButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        root.addArrangedSubview(header)
        root.addArrangedSubview(Self.separator())
        root.addArrangedSubview(contentStack)
        root.addArrangedSubview(Self.separator())
        root.addArrangedSubview(controls)
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 370)
        ])
    }

    private func render() {
        coordinator.refresh()
        let state = coordinator.state

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        connectionLabel.stringValue = coordinator.putIOStatus
        refreshedLabel.stringValue = "Updated \(Self.timeFormatter.string(from: state.lastUpdated))"

        let remoteHeader = sectionHeader("Put.io transfers")
        contentStack.addArrangedSubview(remoteHeader)

        if state.transfers.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No active transfers"))
        } else {
            state.transfers.forEach { contentStack.addArrangedSubview(remoteRow($0)) }
        }

        contentStack.addArrangedSubview(remoteFilesHeader())
        if state.remoteFiles.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No files at this Put.io location"))
        } else {
            state.remoteFiles.forEach { contentStack.addArrangedSubview(remoteFileRow($0)) }
        }

        contentStack.addArrangedSubview(sectionHeader("Local library queue"))
        if state.localJobs.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("Nothing waiting for the SSD"))
        } else {
            state.localJobs.forEach { contentStack.addArrangedSubview(localRow($0)) }
        }
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func remoteFilesHeader() -> NSView {
        let title = sectionHeader("Files in Put.io · \(coordinator.remoteFolderName)")
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

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
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
        stack.widthAnchor.constraint(equalToConstant: 330).isActive = true
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
        stack.widthAnchor.constraint(equalToConstant: 330).isActive = true
        return stack
    }

    private func remoteFileRow(_ file: RemoteFile) -> NSView {
        let title = NSTextField(labelWithString: file.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail

        let details = NSTextField(labelWithString: "\(file.type.displayName) · \(Self.bytes(file.sizeBytes))")
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
            let syncButton = NSButton(title: isQueued(file) ? "Queued" : "Sync", target: self, action: #selector(syncFile(_:)))
            syncButton.bezelStyle = .rounded
            syncButton.tag = file.id
            syncButton.isEnabled = !isQueued(file)
            copy.addArrangedSubview(syncButton)
        }

        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.widthAnchor.constraint(equalToConstant: 330).isActive = true
        return copy
    }

    private func isQueued(_ file: RemoteFile) -> Bool {
        coordinator.state.localJobs.contains(where: { $0.remoteFileID == file.id })
    }

    @objc private func refresh(_ sender: Any?) {
        Task { @MainActor in
            await coordinator.refreshFromPutIO()
            render()
        }
    }

    @objc func settings(_ sender: Any?) {
        onSettings()
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
