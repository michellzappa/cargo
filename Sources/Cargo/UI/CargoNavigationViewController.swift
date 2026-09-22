import AppKit

/// Sidebar + content split. Owns one view controller per page and swaps them in the detail pane.
@MainActor
final class CargoNavigationViewController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: CargoCoordinator
    private let sidebarTableView = NSTableView()
    private let connectionDot = NSView()
    private let connectionLabel = Theme.label(style: .detail, lineBreak: .byTruncatingTail)
    private let updatedLabel = Theme.label(style: .caption)
    private let diskLabel = Theme.label(style: .caption)
    private let diskIndicator = NSProgressIndicator()
    private var emptyingTrash = false
    private lazy var emptyTrashMenuItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Empty Put.io Trash…",
            action: #selector(emptyPutIOTrashFromMenu(_:)),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()
    private lazy var storageMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(emptyTrashMenuItem)
        return menu
    }()
    private let ssdLabel = Theme.label(style: .caption)
    private let ssdIndicator = NSProgressIndicator()
    private let contentContainer = NSViewController()
    private var pages: [Page: PageViewController] = [:]
    private(set) var selectedPage: Page = .transfers

    /// Called when the page or its subtitle changes so the window can update its title.
    var onSelectionChange: ((Page, String) -> Void)?

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: makeSidebarViewController())
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        contentContainer.view = NSView()
        let contentItem = NSSplitViewItem(viewController: contentContainer)
        contentItem.minimumThickness = 560
        contentItem.titlebarSeparatorStyle = .line

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.autosaveName = "CargoMainSplit"

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chillSearchRequested),
            name: CargoCoordinator.didRequestChillSearch,
            object: coordinator
        )
        select(.transfers)
        updateFooter()
    }

    func select(_ page: Page) {
        selectedPage = page
        let controller = pages[page] ?? {
            let controller = page.makeViewController(coordinator: coordinator)
            pages[page] = controller
            return controller
        }()

        for child in contentContainer.children where child !== controller {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        if controller.parent == nil {
            contentContainer.addChild(controller)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.view.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: contentContainer.view.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentContainer.view.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: contentContainer.view.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentContainer.view.bottomAnchor)
            ])
        }

        if sidebarTableView.selectedRow != page.rawValue {
            sidebarTableView.selectRowIndexes(IndexSet(integer: page.rawValue), byExtendingSelection: false)
        }
        onSelectionChange?(page, controller.subtitle)
    }

    var currentPage: PageViewController? { pages[selectedPage] }

    @objc private func coordinatorDidChange() {
        sidebarTableView.reloadData(forRowIndexes: IndexSet(0..<Page.allCases.count), columnIndexes: IndexSet(integer: 0))
        updateFooter()
        if let controller = pages[selectedPage] {
            onSelectionChange?(selectedPage, controller.subtitle)
        }
    }

    @objc private func chillSearchRequested() {
        select(.discover)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.searchChill(query: coordinator.chillSearchQuery)
        }
    }

    // MARK: - Sidebar

    private func makeSidebarViewController() -> NSViewController {
        let controller = NSViewController()
        let root = NSView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CargoSidebar"))
        column.resizingMask = .autoresizingMask
        sidebarTableView.addTableColumn(column)
        sidebarTableView.headerView = nil
        sidebarTableView.style = .sourceList
        sidebarTableView.rowHeight = 28
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.allowsEmptySelection = false
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        scrollView.documentView = sidebarTableView

        // Footer: connection, last update, Put.io storage.
        connectionDot.wantsLayer = true
        connectionDot.layer?.cornerRadius = 4
        connectionDot.translatesAutoresizingMaskIntoConstraints = false
        connectionDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        connectionDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let connectionRow = NSStackView(views: [connectionDot, connectionLabel])
        connectionRow.orientation = .horizontal
        connectionRow.alignment = .centerY
        connectionRow.spacing = 6

        for indicator in [diskIndicator, ssdIndicator] {
            indicator.style = .bar
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.controlSize = .small
            indicator.translatesAutoresizingMaskIntoConstraints = false
        }

        // The Put.io storage readout is also the quick path to clearing files
        // that were manually moved to Put.io's trash.
        diskLabel.menu = storageMenu
        diskIndicator.menu = storageMenu

        let footer = NSStackView(views: [connectionRow, updatedLabel, diskLabel, diskIndicator, ssdLabel, ssdIndicator])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 4
        footer.translatesAutoresizingMaskIntoConstraints = false
        diskIndicator.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        ssdIndicator.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        connectionRow.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        footer.setCustomSpacing(10, after: updatedLabel)
        footer.setCustomSpacing(8, after: diskIndicator)

        root.addSubview(scrollView)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        controller.view = root
        return controller
    }

    private func updateFooter() {
        let connected = coordinator.dashboardIsConnected
        connectionDot.layer?.backgroundColor = (connected ? NSColor.systemGreen : NSColor.systemGray).cgColor
        connectionLabel.stringValue = connected
            ? coordinator.dashboardPutIOStatus.replacingOccurrences(of: "Connected as ", with: "")
            : coordinator.dashboardPutIOStatus
        connectionLabel.toolTip = coordinator.dashboardPutIOStatus
        updatedLabel.stringValue = "Updated \(Formatters.time.string(from: coordinator.dashboardState.lastUpdated))"

        if let disk = coordinator.dashboardDiskUsage {
            diskLabel.stringValue = "Put.io · \(Formatters.shortBytes(disk.availableBytes)) free"
            diskLabel.toolTip = "\(Formatters.bytes(disk.usedBytes)) used of \(Formatters.bytes(disk.totalBytes))"
            diskIndicator.doubleValue = disk.fraction
            emptyTrashMenuItem.isEnabled = !coordinator.isRemoteClientMode
                && (coordinator.trashSummary?.count ?? 0) > 0
                && !emptyingTrash
            diskLabel.isHidden = false
            diskIndicator.isHidden = false
        } else {
            emptyTrashMenuItem.isEnabled = false
            diskLabel.stringValue = connected ? "Put.io · Availability unavailable" : "Put.io · Not connected"
            diskLabel.toolTip = coordinator.dashboardPutIOStatus
            diskLabel.isHidden = false
            diskIndicator.isHidden = true
        }

        if coordinator.isRemoteClientMode {
            ssdLabel.stringValue = "SSD · Resident only"
            ssdLabel.toolTip = "The resident Mac owns the local SSD."
            ssdLabel.isHidden = false
            ssdIndicator.isHidden = true
            return
        }

        // The library volume: same shape as the Put.io line, so the two read together.
        if let root = coordinator.libraryRootURL(),
           let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeNameKey]),
           let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity, total > 0 {
            let volumeName = values.volumeName ?? "SSD"
            let repairSuffix = coordinator.libraryRootBookmarkNeedsRepair ? " · bookmark repair needed" : ""
            ssdLabel.stringValue = "\(volumeName) · \(Formatters.shortBytes(free)) free\(repairSuffix)"
            ssdLabel.toolTip = coordinator.libraryRootBookmarkNeedsRepair
                ? "\(Formatters.bytes(Int64(total) - free)) used of \(Formatters.bytes(Int64(total))). The saved path is working without prompting; re-select the library root in Settings only if you want to renew its bookmark."
                : "\(Formatters.bytes(Int64(total) - free)) used of \(Formatters.bytes(Int64(total)))"
            ssdIndicator.doubleValue = 1 - Double(free) / Double(total)
            ssdLabel.isHidden = false
            ssdIndicator.isHidden = false
        } else {
            if coordinator.state.settings.libraryRootPath == nil {
                ssdLabel.stringValue = "SSD · Library not configured"
                ssdLabel.toolTip = "Choose a library root in Cargo Settings."
            } else {
                ssdLabel.stringValue = "SSD · Access unavailable"
                ssdLabel.toolTip = "Re-select the library root in Cargo Settings to refresh its permission bookmark."
            }
            ssdLabel.isHidden = false
            ssdIndicator.isHidden = true
        }
    }

    @objc private func emptyPutIOTrashFromMenu(_ sender: Any?) {
        guard !emptyingTrash else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Put.io trash?"
        alert.informativeText = "Everything in the trash is deleted for good. This includes files you trashed outside Cargo."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        emptyingTrash = true
        emptyTrashMenuItem.isEnabled = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.emptyingTrash = false
                self.updateFooter()
            }
            do {
                try await coordinator.emptyPutIOTrash()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        Page.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let page = Page(rawValue: row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SidebarCellView
            ?? SidebarCellView(identifier: identifier)
        cell.configure(title: page.title, symbol: page.symbolName, count: page.count(in: coordinator))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let page = Page(rawValue: sidebarTableView.selectedRow), page != selectedPage else { return }
        select(page)
    }
}

/// Source-list row: icon, title, muted count (no accent pill — matches Finder/Mail).
private final class SidebarCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = Theme.label(style: .body)
    private let countLabel = Theme.label(style: .detail)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(countLabel)
        imageView = iconView
        textField = titleLabel
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, symbol: String, count: Int) {
        iconView.image = Theme.symbol(symbol, pointSize: 14, weight: .regular)
        titleLabel.stringValue = title
        countLabel.stringValue = count > 0 ? String(count) : ""
    }
}
