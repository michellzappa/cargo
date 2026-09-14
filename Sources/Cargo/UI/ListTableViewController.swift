import AppKit

/// One action a row offers — as the trailing button, in the context menu, or both.
struct RowAction {
    /// Asked once before the handler runs — once for the whole selection when
    /// several rows are selected, so a multi-delete is one dialog, not ten.
    struct Confirmation {
        let message: String
        let detail: String
        let button: String
        /// Message when applied to several rows; `%d` is the count.
        var pluralMessage: String? = nil
    }

    let title: String
    var isDestructive = false
    var isEnabled = true
    var isSeparatorBefore = false
    var confirmation: Confirmation? = nil
    let handler: @MainActor () -> Void

    static func separator() -> RowAction {
        RowAction(title: "", isSeparatorBefore: true) {}
    }
}

/// Everything a list needs to draw one row. Pages build these; the table renders them.
struct ListRow {
    let id: String
    let title: String
    var titleColor: NSColor? = nil
    var details: [String] = []
    var badge: StatusBadge? = nil
    var progress: Double? = nil
    /// Poster/artwork shown at the leading edge, loaded lazily.
    var thumbnail: URL? = nil
    var primaryAction: RowAction? = nil
    var menuActions: [RowAction] = []
}

struct ListSection {
    var title: String? = nil
    var rows: [ListRow]
}

struct EmptyState {
    let symbol: String
    let title: String
    var detail: String? = nil
}

/// Native table-backed list shared by every page: inset style, automatic row heights,
/// group rows for sections, context menus, double-click → primary action, empty state.
@MainActor
final class ListTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private enum Item {
        case header(String)
        case row(ListRow)
    }

    private let tableView = ListTableView()
    private let scrollView = NSScrollView()
    private let emptyStateView = NSStackView()
    private let emptySymbolView = NSImageView()
    private let emptyTitleLabel = Theme.label(style: .body, color: .secondaryLabelColor)
    private let emptyDetailLabel = Theme.label(style: .detail, wraps: true)
    private let contextMenu = NSMenu()
    private var items: [Item] = []
    private var menuActions: [RowAction] = []

    var emptyState = EmptyState(symbol: "tray", title: "Nothing here") {
        didSet { updateEmptyState() }
    }
    /// Shown when right-clicking empty space (e.g. Refresh, Add transfer).
    var listActions: [RowAction] = []

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ListColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        // Actions apply to every selected row; ⌫ runs the destructive one.
        tableView.allowsMultipleSelection = true
        tableView.onDeleteKey = { [weak self] in self?.performDestructiveActionOnSelection() }
        tableView.floatsGroupRows = false
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))
        tableView.menu = contextMenu
        contextMenu.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        emptySymbolView.symbolConfiguration = .init(pointSize: 36, weight: .light)
        emptySymbolView.contentTintColor = .tertiaryLabelColor
        emptyTitleLabel.alignment = .center
        emptyDetailLabel.alignment = .center
        emptyDetailLabel.preferredMaxLayoutWidth = 360
        emptyStateView.orientation = .vertical
        emptyStateView.alignment = .centerX
        emptyStateView.spacing = 8
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addArrangedSubview(emptySymbolView)
        emptyStateView.addArrangedSubview(emptyTitleLabel)
        emptyStateView.addArrangedSubview(emptyDetailLabel)
        emptyStateView.setCustomSpacing(14, after: emptySymbolView)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            emptyStateView.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
        updateEmptyState()
    }

    // MARK: - Data

    func apply(_ sections: [ListSection]) {
        let selectedID = selectedRow?.id
        items = sections.flatMap { section -> [Item] in
            guard !section.rows.isEmpty else { return [] }
            var result: [Item] = []
            if let title = section.title { result.append(.header(title)) }
            result.append(contentsOf: section.rows.map(Item.row))
            return result
        }
        tableView.reloadData()
        if let selectedID, let index = items.firstIndex(where: {
            if case .row(let row) = $0 { return row.id == selectedID }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateEmptyState()
    }

    private var selectedRow: ListRow? {
        row(at: tableView.selectedRow)
    }

    private func row(at index: Int) -> ListRow? {
        guard items.indices.contains(index), case .row(let row) = items[index] else { return nil }
        return row
    }

    private func updateEmptyState() {
        emptySymbolView.image = Theme.symbol(emptyState.symbol, pointSize: 36, weight: .light)
        emptyTitleLabel.stringValue = emptyState.title
        emptyDetailLabel.stringValue = emptyState.detail ?? ""
        emptyDetailLabel.isHidden = emptyState.detail == nil
        let isEmpty = items.isEmpty
        emptyStateView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        !self.tableView(tableView, isGroupRow: row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        switch items[index] {
        case .header(let title):
            let identifier = NSUserInterfaceItemIdentifier("SectionHeader")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SectionHeaderCellView
                ?? SectionHeaderCellView(identifier: identifier)
            cell.title = title
            return cell
        case .row(let row):
            let identifier = NSUserInterfaceItemIdentifier("ListCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ListCellView
                ?? ListCellView(identifier: identifier)
            cell.configure(with: row)
            return cell
        }
    }

    @objc private func handleDoubleClick(_ sender: Any?) {
        guard let row = row(at: tableView.clickedRow), let action = row.primaryAction, action.isEnabled else { return }
        action.handler()
    }

    // MARK: - Context menu

    /// The rows an action applies to: the whole selection when the clicked
    /// row is part of it, otherwise just the clicked row.
    private var targetRows: [ListRow] {
        let clicked = tableView.clickedRow
        let selected = tableView.selectedRowIndexes
        let indexes = clicked >= 0 && !selected.contains(clicked) ? IndexSet(integer: clicked) : selected
        return indexes.compactMap(row(at:))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rows = targetRows
        guard let first = rows.first else {
            menuActions = listActions
            build(menu, from: menuActions, count: 1)
            return
        }
        // Only actions every selected row offers, so a mixed selection can't do the wrong thing.
        menuActions = first.menuActions.filter { action in
            rows.allSatisfy { row in row.menuActions.contains { $0.title == action.title } }
        }
        build(menu, from: menuActions, count: rows.count)
    }

    private func build(_ menu: NSMenu, from actions: [RowAction], count: Int) {
        for (index, action) in actions.enumerated() {
            if action.isSeparatorBefore {
                menu.addItem(.separator())
                if action.title.isEmpty { continue }
            }
            let title = count > 1 ? "\(action.title)  (\(count))" : action.title
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = action.isEnabled
            if action.isDestructive {
                item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            menu.addItem(item)
        }
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard menuActions.indices.contains(sender.tag) else { return }
        let template = menuActions[sender.tag]
        let rows = targetRows
        guard !rows.isEmpty else {
            template.handler()
            return
        }
        perform(template, on: rows)
    }

    private func perform(_ template: RowAction, on rows: [ListRow]) {
        let actions = rows.compactMap { row in row.menuActions.first { $0.title == template.title && $0.isEnabled } }
        guard !actions.isEmpty else { return }
        if let confirmation = template.confirmation {
            let alert = NSAlert()
            alert.messageText = actions.count > 1
                ? String(format: confirmation.pluralMessage ?? "%d items — \(confirmation.message)", actions.count)
                : confirmation.message
            alert.informativeText = confirmation.detail
            alert.addButton(withTitle: confirmation.button)
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = template.isDestructive
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        for action in actions { action.handler() }
    }

    private func performDestructiveActionOnSelection() {
        let rows = tableView.selectedRowIndexes.compactMap(row(at:))
        guard let first = rows.first,
              let template = first.menuActions.first(where: { $0.isDestructive && $0.isEnabled })
        else { return }
        perform(template, on: rows)
    }
}

/// Forwards ⌫ / ⌦ so the list can run the row's destructive action.
private final class ListTableView: NSTableView {
    var onDeleteKey: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, selectedRow >= 0 {
            onDeleteKey()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Cells

private final class SectionHeaderCellView: NSTableCellView {
    private let label = Theme.label(style: .sectionHeader, color: .secondaryLabelColor)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}

private final class ListCellView: NSTableCellView {
    private let titleLabel = Theme.label(style: .rowTitle)
    private let badgeView = StatusBadgeView()
    private let detailLabels = (0..<3).map { _ in Theme.label(style: .detail, lineBreak: .byTruncatingMiddle) }
    private let progressIndicator = NSProgressIndicator()
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let textStack = NSStackView()
    private let thumbnailView = NSImageView()
    private var thumbnailLeading: NSLayoutConstraint!
    private var thumbnailWidth: NSLayoutConstraint!
    private var thumbnailHeight: NSLayoutConstraint!
    private var thumbnailURL: URL?
    private var action: RowAction?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.setContentHuggingPriority(.required, for: .vertical)
        thumbnailView.setContentCompressionResistancePriority(.init(1), for: .vertical)
        thumbnailView.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        addSubview(thumbnailView)

        let titleRow = NSStackView(views: [titleLabel, badgeView])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleRow)
        textStack.addArrangedSubview(progressIndicator)
        detailLabels.forEach(textStack.addArrangedSubview)
        titleRow.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        progressIndicator.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        detailLabels.forEach { $0.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true }

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(performAction(_:))
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        textStack.setContentHuggingPriority(.init(1), for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(textStack)
        addSubview(actionButton)
        thumbnailWidth = thumbnailView.widthAnchor.constraint(equalToConstant: 0)
        thumbnailHeight = thumbnailView.heightAnchor.constraint(equalToConstant: 0)
        thumbnailLeading = textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            thumbnailHeight,
            thumbnailWidth,
            thumbnailLeading,
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 12),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with row: ListRow) {
        thumbnailURL = row.thumbnail
        if let url = row.thumbnail {
            thumbnailWidth.constant = 40
            thumbnailHeight.constant = 60
            thumbnailLeading.constant = 10
            thumbnailView.isHidden = false
            thumbnailView.image = nil
            Task { @MainActor [weak self] in
                let image = await PosterCache.shared.image(for: url)
                guard let self, self.thumbnailURL == url else { return }
                self.thumbnailView.image = image
            }
        } else {
            thumbnailWidth.constant = 0
            thumbnailHeight.constant = 0
            thumbnailLeading.constant = 0
            thumbnailView.isHidden = true
        }
        titleLabel.stringValue = row.title
        titleLabel.textColor = row.titleColor ?? Theme.LabelStyle.rowTitle.color
        badgeView.badge = row.badge

        for (index, label) in detailLabels.enumerated() {
            if row.details.indices.contains(index) {
                label.stringValue = row.details[index]
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }

        if let progress = row.progress {
            progressIndicator.doubleValue = progress
            progressIndicator.isHidden = false
        } else {
            progressIndicator.isHidden = true
        }

        action = row.primaryAction
        if let action = row.primaryAction {
            actionButton.title = action.title
            actionButton.isEnabled = action.isEnabled
            actionButton.hasDestructiveAction = action.isDestructive
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
    }

    @objc private func performAction(_ sender: Any?) {
        action?.handler()
    }
}
