import AppKit

enum CargoSearchDestination {
    case discover(query: String)
    case library(id: String)
    case watchlist(id: String)
}

struct CargoSearchResult {
    let title: String
    let detail: String
    let symbolName: String
    let destination: CargoSearchDestination
}

/// The app-wide Cmd-K search palette. It is intentionally local-first: the
/// library and watchlist are searched from cached state, while Discover is an
/// explicit hand-off to the existing Chill search.
@MainActor
final class CargoSearchWindowController: NSWindowController {
    private static let paletteSize = NSSize(width: 680, height: 500)
    private let searchViewController: CargoSearchViewController

    init(coordinator: CargoCoordinator, onSelect: @escaping (CargoSearchResult) -> Void) {
        searchViewController = CargoSearchViewController(coordinator: coordinator, onSelect: onSelect)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.paletteSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.title = "Search Cargo"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.contentViewController = searchViewController
        // AppKit can derive a panel's frame from a programmatic content view
        // when the view has no intrinsic size. Keep the Cmd-K palette wide
        // enough for its search field and result rows.
        panel.setContentSize(Self.paletteSize)
        panel.contentMinSize = Self.paletteSize
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(relativeTo parent: NSWindow?) {
        window?.setContentSize(Self.paletteSize)
        if let parent, let window, window.parent !== parent {
            parent.addChildWindow(window, ordered: .above)
        }

        if let parent, let window {
            let size = window.frame.size
            let x = parent.frame.midX - size.width / 2
            let y = parent.frame.maxY - 150 - size.height
            window.setFrameOrigin(NSPoint(x: x, y: max(parent.frame.minY + 24, y)))
        } else {
            window?.center()
        }

        searchViewController.prepareForDisplay()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchViewController.searchField)
    }
}

@MainActor
private final class CargoSearchViewController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = CargoSearchField()
    private let coordinator: CargoCoordinator
    private let onSelect: (CargoSearchResult) -> Void
    private let tableView = CargoSearchTableView()
    private let catalogueLabel = Theme.label(style: .caption, color: .tertiaryLabelColor)
    private let statusLabel = Theme.label(style: .caption, color: .secondaryLabelColor)
    private var results: [CargoSearchResult] = []

    init(coordinator: CargoCoordinator, onSelect: @escaping (CargoSearchResult) -> Void) {
        self.coordinator = coordinator
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        view = background

        searchField.placeholderString = "Search Library, Watchlist, or Discover"
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 16)
        searchField.focusRingType = .default
        searchField.delegate = self
        searchField.onMove = { [weak self] delta in self?.moveSelection(by: delta) }
        searchField.onEnter = { [weak self] in self?.activateSelection(nil) }
        searchField.onDismiss = { [weak self] in self?.view.window?.close() }
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CargoSearchResults"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(activateSelection(_:))
        tableView.onEnter = { [weak self] in self?.activateSelection(nil) }
        tableView.onDismiss = { [weak self] in self?.view.window?.close() }
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        catalogueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.alignment = .right

        let footer = NSStackView(views: [catalogueLabel, NSView(), statusLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            searchField.heightAnchor.constraint(equalToConstant: 32),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            footer.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        updateResults()
    }

    func prepareForDisplay() {
        if !isViewLoaded { loadViewIfNeeded() }
        searchField.stringValue = ""
        updateResults()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateResults()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchField else { return false }

        switch NSStringFromSelector(commandSelector) {
        case "moveDown:", "moveDownAndModifySelection:":
            moveSelection(by: 1)
            return true
        case "moveUp:", "moveUpAndModifySelection:":
            moveSelection(by: -1)
            return true
        case "insertNewline:", "insertLineBreak:":
            activateSelection(nil)
            return true
        case "cancelOperation:":
            view.window?.close()
            return true
        default:
            return false
        }
    }

    @objc private func coordinatorDidChange() {
        updateResults()
    }

    @objc func activateSelection(_ sender: Any?) {
        let index = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard results.indices.contains(index) else { return }
        onSelect(results[index])
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        let next: Int
        if current < 0 {
            next = delta >= 0 ? 0 : results.count - 1
        } else {
            next = min(max(current + delta, 0), results.count - 1)
        }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("CargoSearchResultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? CargoSearchResultCell
            ?? CargoSearchResultCell(identifier: identifier)
        cell.configure(with: results[row])
        return cell
    }

    private func updateResults() {
        guard isViewLoaded else { return }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = CargoSearchIndex.results(for: query, state: coordinator.state)
        tableView.reloadData()
        tableView.deselectAll(nil)
        let movieCount = coordinator.state.libraryItems.filter { $0.kind == .movie }.count
        let showCount = coordinator.state.libraryItems.filter { $0.kind == .show }.count
        let watchlistCount = coordinator.state.imdbWatchlistItems.count
        catalogueLabel.stringValue = "\(movieCount) movies · \(showCount) TV shows · \(watchlistCount) watchlist"
        if query.isEmpty {
            statusLabel.stringValue = "Type to search · ↑↓ navigate · Return open"
        } else if results.isEmpty {
            statusLabel.stringValue = "No matches · Esc close"
        } else {
            statusLabel.stringValue = "\(results.count) result\(results.count == 1 ? "" : "s") · ↑↓ navigate · Return open"
        }
    }
}

@MainActor
private final class CargoSearchField: NSSearchField {
    var onMove: (Int) -> Void = { _ in }
    var onEnter: () -> Void = {}
    var onDismiss: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return / keypad Enter
            onEnter()
        case 125: // Down
            onMove(1)
        case 126: // Up
            onMove(-1)
        case 53: // Escape
            onDismiss()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class CargoSearchTableView: NSTableView {
    var onEnter: () -> Void = {}
    var onDismiss: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter()
            return
        }
        if event.keyCode == 53 {
            onDismiss()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class CargoSearchResultCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = Theme.label(style: .body)
    private let detailLabel = Theme.label(style: .detail)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labels)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with result: CargoSearchResult) {
        iconView.image = Theme.symbol(result.symbolName, pointSize: 16, weight: .medium)
        titleLabel.stringValue = result.title
        detailLabel.stringValue = result.detail
    }
}

@MainActor
private enum CargoSearchIndex {
    static func results(for query: String, state: CargoState) -> [CargoSearchResult] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        func matches(_ values: [String]) -> Bool {
            let haystack = normalize(values.joined(separator: " "))
            return tokens.allSatisfy { haystack.contains($0) }
        }

        var results: [CargoSearchResult] = []
        results.append(CargoSearchResult(
            title: "Search Discover for “\(query)”",
            detail: "Chill release search",
            symbolName: "sparkles",
            destination: .discover(query: query)
        ))

        results += state.libraryItems.filter { item in
            matches([item.title, item.displayTitle, item.relativePath, item.year.map(String.init) ?? ""])
        }.map { item in
            CargoSearchResult(
                title: item.displayTitle,
                detail: "Library · \(item.kind == .movie ? "Movie" : "TV Show")",
                symbolName: item.kind == .movie ? "film" : "tv",
                destination: .library(id: item.id)
            )
        }

        results += state.imdbWatchlistItems.filter { item in
            matches([item.title, item.id, item.year.map(String.init) ?? "", item.titleType ?? ""])
        }.map { item in
            let status = WatchlistPageViewController.status(for: item, state: state).text
            return CargoSearchResult(
                title: item.year.map { "\(item.title) (\($0))" } ?? item.title,
                detail: "Watchlist · \(status)",
                symbolName: "star",
                destination: .watchlist(id: item.id)
            )
        }

        return results.sorted { lhs, rhs in
            let lhsExact = normalize(lhs.title) == normalizedQuery
            let rhsExact = normalize(rhs.title) == normalizedQuery
            if lhsExact != rhsExact { return lhsExact }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }
}
