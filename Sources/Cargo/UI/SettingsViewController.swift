import AppKit

final class SettingsViewController: NSViewController {
    private struct WorkflowStep {
        let number: Int
        let symbolName: String
        let title: String
        let detail: String
        let status: String
        let actionTitle: String
    }

    private let workflowSteps = [
        WorkflowStep(
            number: 1,
            symbolName: "person.crop.circle",
            title: "Connect Put.io",
            detail: "Store the account token securely and test the connection.",
            status: "Not connected yet",
            actionTitle: "Configure"
        ),
        WorkflowStep(
            number: 2,
            symbolName: "arrow.triangle.2.circlepath",
            title: "Observe remote transfers",
            detail: "Watch the queue that ShowRSS is already feeding in Put.io.",
            status: "Read-only monitor",
            actionTitle: "Configure"
        ),
        WorkflowStep(
            number: 3,
            symbolName: "externaldrive",
            title: "Sync completed files",
            detail: "Choose where completed Put.io files should land on the SSD.",
            status: "Destination not configured",
            actionTitle: "Choose folder"
        ),
        WorkflowStep(
            number: 4,
            symbolName: "folder.badge.gearshape",
            title: "Organize the library",
            detail: "Identify media and place it into the Movies and TV Shows folders.",
            status: "Ready after folders are set",
            actionTitle: "Configure"
        ),
        WorkflowStep(
            number: 5,
            symbolName: "captions.bubble",
            title: "Run post-import automation",
            detail: "Leave a clean extension point for EasySubs after import succeeds.",
            status: "Not configured",
            actionTitle: "Configure"
        ),
        WorkflowStep(
            number: 6,
            symbolName: "bell",
            title: "Notify on meaningful changes",
            detail: "Get alerts for completed syncs, failures, and missing volumes.",
            status: "Notifications enabled",
            actionTitle: "Configure"
        )
    ]

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
    }

    private func buildInterface() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Workflow settings")
        title.font = .systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Cargo is configured in the same order that it moves media.")
        subtitle.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(Self.separator())

        for step in workflowSteps {
            stack.addArrangedSubview(stepRow(step))
        }

        let container = NSView()
        container.addSubview(stack)
        scrollView.documentView = container
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func stepRow(_ step: WorkflowStep) -> NSView {
        let icon = NSImageView(image: NSImage(
            systemSymbolName: step.symbolName,
            accessibilityDescription: step.title
        ) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let number = NSTextField(labelWithString: "\(step.number)")
        number.alignment = .center
        number.font = .systemFont(ofSize: 11, weight: .semibold)
        number.textColor = .secondaryLabelColor
        number.translatesAutoresizingMaskIntoConstraints = false
        number.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let title = NSTextField(labelWithString: step.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        let detail = NSTextField(labelWithString: step.detail)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        detail.lineBreakMode = .byWordWrapping

        let status = NSTextField(labelWithString: step.status)
        status.textColor = .tertiaryLabelColor
        status.font = .systemFont(ofSize: 11, weight: .medium)

        let copy = NSStackView(views: [title, detail, status])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        let action = NSButton(title: step.actionTitle, target: self, action: #selector(configureStep(_:)))
        action.bezelStyle = .rounded
        action.tag = step.number

        let row = NSStackView(views: [number, icon, copy, action])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 600).isActive = true
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    @objc private func configureStep(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Configuration coming next"
        alert.informativeText = "Step \(sender.tag) is represented in the workflow. The live Put.io and SSD settings will be wired in the next build slice."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentViewController: SettingsViewController())
        window.title = "Cargo Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 620))
        window.minSize = NSSize(width: 600, height: 480)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
