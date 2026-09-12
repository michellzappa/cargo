import AppKit

final class DashboardViewController: NSViewController {
    private let coordinator: CargoCoordinator
    private let onSettings: () -> Void
    private let contentStack = NSStackView()
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

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Cargo")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Put.io → local library")
        subtitle.textColor = .secondaryLabelColor

        refreshedLabel.textColor = .tertiaryLabelColor
        refreshedLabel.font = .systemFont(ofSize: 11)

        let header = NSStackView(views: [title, subtitle, refreshedLabel])
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
        refreshedLabel.stringValue = "Updated (Self.timeFormatter.string(from: state.lastUpdated))"

        let remoteHeader = sectionHeader("Put.io transfers")
        contentStack.addArrangedSubview(remoteHeader)

        if state.transfers.isEmpty {
            contentStack.addArrangedSubview(emptyLabel("No remote transfers"))
        } else {
            state.transfers.forEach { contentStack.addArrangedSubview(remoteRow($0)) }
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

        let stack = NSStackView(views: [title, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 330).isActive = true
        return stack
    }

    @objc private func refresh(_ sender: Any?) {
        render()
    }

    @objc private func settings(_ sender: Any?) {
        onSettings()
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
