import AppKit

@MainActor
final class CargoNavigationViewController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Destination: Int, CaseIterable {
        case transfers
        case files
        case inbox
        case watchlist
        case history
        case settings

        var title: String {
            switch self {
            case .transfers: "Transfers"
            case .files: "Files"
            case .inbox: "Inbox"
            case .watchlist: "Watchlist"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        var symbolName: String {
            switch self {
            case .transfers: "arrow.down.circle"
            case .files: "folder"
            case .inbox: "tray"
            case .watchlist: "star"
            case .history: "clock"
            case .settings: "gearshape"
            }
        }
    }

    private let coordinator: CargoCoordinator
    private let dashboard: DashboardViewController
    private let sidebarTableView = NSTableView()

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        self.dashboard = DashboardViewController(coordinator: coordinator)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarViewController = makeSidebarViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 178
        sidebarItem.maximumThickness = 240
        sidebarItem.canCollapse = false

        let contentItem = NSSplitViewItem(viewController: dashboard)
        contentItem.minimumThickness = 560
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.setPosition(198, ofDividerAt: 0)

        select(.transfers)
    }

    func refreshView() {
        dashboard.refreshView()
        sidebarTableView.reloadData()
    }

    func showSettings() {
        select(.settings)
    }

    private func select(_ destination: Destination) {
        dashboard.selectView(destination.rawValue)
        guard isViewLoaded else { return }
        sidebarTableView.selectRowIndexes(
            IndexSet(integer: destination.rawValue),
            byExtendingSelection: false
        )
        sidebarTableView.scrollRowToVisible(destination.rawValue)
    }

    private func makeSidebarViewController() -> NSViewController {
        let sidebarViewController = NSViewController()
        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CargoSidebar"))
        column.resizingMask = .autoresizingMask
        sidebarTableView.addTableColumn(column)
        sidebarTableView.headerView = nil
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.selectionHighlightStyle = .regular
        sidebarTableView.rowHeight = 34
        sidebarTableView.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTableView.style = .sourceList
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        scrollView.documentView = sidebarTableView

        effectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12)
        ])

        sidebarViewController.view = effectView
        return sidebarViewController
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        Destination.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let destination = Destination(rawValue: row) else { return nil }

        let cell = NSTableCellView()
        let iconView = NSImageView(
            image: NSImage(systemSymbolName: destination.symbolName, accessibilityDescription: destination.title)
                ?? NSImage()
        )
        iconView.contentTintColor = .secondaryLabelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: destination.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: badgeText(for: destination))
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.isHidden = badge.stringValue.isEmpty
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.layer?.cornerRadius = 8
        badge.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iconView)
        cell.addSubview(titleLabel)
        cell.addSubview(badge)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 17)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        guard let destination = Destination(rawValue: row) else { return }
        dashboard.selectView(destination.rawValue)
    }

    private func badgeText(for destination: Destination) -> String {
        switch destination {
        case .inbox:
            let count = coordinator.inboxFileURLs().count
            return count > 0 ? String(count) : ""
        case .watchlist:
            let count = coordinator.state.imdbWatchlistItems.count
            return count > 0 ? String(count) : ""
        case .transfers:
            let count = coordinator.state.transfers.count
            return count > 0 ? String(count) : ""
        case .files, .history, .settings:
            return ""
        }
    }
}
