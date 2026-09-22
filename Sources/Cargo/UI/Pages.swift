import AppKit

/// Sidebar destinations. Settings lives in its own window (⌘,).
enum Page: Int, CaseIterable {
    case discover
    case transfers
    case files
    case inbox
    case library
    case watchlist
    case history

    var title: String {
        switch self {
        case .discover: "Discover"
        case .transfers: "Transfers"
        case .files: "Files"
        case .inbox: "Inbox"
        case .library: "Library"
        case .watchlist: "Watchlist"
        case .history: "History"
        }
    }

    var symbolName: String {
        switch self {
        case .discover: "sparkles"
        case .transfers: "arrow.down.circle"
        case .files: "folder"
        case .inbox: "tray"
        case .library: "film.stack"
        case .watchlist: "star"
        case .history: "clock"
        }
    }

    @MainActor
    func count(in coordinator: CargoCoordinator) -> Int {
        switch self {
        case .discover: coordinator.dashboardChillSearchResults.count
        case .transfers: coordinator.dashboardState.transfers.count
        case .files: coordinator.dashboardState.remoteMediaFiles.count
        case .inbox: coordinator.isRemoteClientMode
            ? coordinator.dashboardState.localJobs.filter { $0.status != .completed }.count
            : coordinator.inboxFileURLs().count
        case .library: coordinator.dashboardState.libraryItems.count
        case .watchlist: coordinator.dashboardState.imdbWatchlistItems.count
        case .history: coordinator.dashboardState.history.count
        }
    }

    @MainActor
    func makeViewController(coordinator: CargoCoordinator) -> PageViewController {
        switch self {
        case .discover: DiscoverPageViewController(page: self, coordinator: coordinator)
        case .transfers: TransfersPageViewController(page: self, coordinator: coordinator)
        case .files: FilesPageViewController(page: self, coordinator: coordinator)
        case .inbox: InboxPageViewController(page: self, coordinator: coordinator)
        case .library: LibraryPageViewController(page: self, coordinator: coordinator)
        case .watchlist: WatchlistPageViewController(page: self, coordinator: coordinator)
        case .history: HistoryPageViewController(page: self, coordinator: coordinator)
        }
    }
}

/// A segmented control with the separated, soft capsules used by the page toolbars.
/// It keeps NSSegmentedControl's target/action API so the pages can share one control
/// without changing their existing filtering behavior.
@MainActor
final class ModernPillControl: NSSegmentedControl {
    private let segmentGap: CGFloat = 6
    private let horizontalPadding: CGFloat = 18
    private let controlHeight: CGFloat = 36

    override var selectedSegment: Int {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: segmentWidths.reduce(0, +) + CGFloat(max(segmentCount - 1, 0)) * segmentGap,
               height: controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = self.font ?? .systemFont(ofSize: 14, weight: .medium)
        let rects = segmentRects(font: font)

        for (index, rect) in rects.enumerated() {
            let isSelected = index == selectedSegment
            let fillColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.58)
            let borderColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.30)
                : NSColor.separatorColor.withAlphaComponent(0.30)

            fillColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            borderColor.setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: rect.height / 2,
                                      yRadius: rect.height / 2)
            border.lineWidth = 1
            border.stroke()

            let title = label(forSegment: index) ?? ""
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            ]
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: rect.midX - titleSize.width / 2,
                                   y: rect.midY - titleSize.height / 2 + 1),
                       withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rects = segmentRects(font: font ?? .systemFont(ofSize: 14, weight: .medium))
        guard let index = rects.firstIndex(where: { $0.contains(point) }) else { return }
        selectedSegment = index
        sendAction(action, to: target)
    }

    private var segmentWidths: [CGFloat] {
        let font = self.font ?? .systemFont(ofSize: 14, weight: .medium)
        return (0..<segmentCount).map { index in
            max(52, (label(forSegment: index) ?? "").size(withAttributes: [.font: font]).width + horizontalPadding * 2)
        }
    }

    private func segmentRects(font: NSFont) -> [NSRect] {
        var x: CGFloat = 0
        let height = min(controlHeight, bounds.height)
        let y = bounds.midY - height / 2
        return segmentWidths.map { width in
            defer { x += width + segmentGap }
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }
}

/// A popup button that preserves AppKit menus while drawing a larger, quieter capsule.
@MainActor
final class ModernPillPopupButton: NSPopUpButton {
    private let controlHeight: CGFloat = 36

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        (isEnabled ? NSColor.controlBackgroundColor.withAlphaComponent(0.62) : NSColor.controlBackgroundColor.withAlphaComponent(0.40)).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(isEnabled ? 0.32 : 0.20).setStroke()
        path.lineWidth = 1
        path.stroke()

        let font = self.font ?? .systemFont(ofSize: 14, weight: .medium)
        let textColor = isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let currentTitle = selectedItem?.title ?? self.title
        var textRect = rect.insetBy(dx: 14, dy: 0)

        if let image {
            let imageRect = NSRect(x: textRect.minX,
                                   y: rect.midY - 8,
                                   width: 16,
                                   height: 16)
            image.draw(in: imageRect)
            textRect.origin.x += 23
            textRect.size.width -= 23
        }

        let chevron = Theme.symbol("chevron.down", pointSize: 11, weight: .semibold)
        if let chevron {
            chevron.draw(in: NSRect(x: rect.maxX - 27, y: rect.midY - 6, width: 12, height: 12))
        }
        textRect.size.width -= 22
        let titleSize = currentTitle.size(withAttributes: attributes)
        currentTitle.draw(at: NSPoint(x: textRect.minX,
                                     y: rect.midY - titleSize.height / 2 + 1),
                          withAttributes: attributes)
    }
}

/// Base for every content page: owns a list table, re-renders on coordinator changes.
@MainActor
class PageViewController: NSViewController {
    let page: Page
    let coordinator: CargoCoordinator
    let list = ListTableViewController()

    /// Secondary line shown under the window title.
    var subtitle: String {
        let count = page.count(in: coordinator)
        return count > 0 ? "\(count)" : ""
    }

    init(page: Page, coordinator: CargoCoordinator) {
        self.page = page
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        title = page.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        addChild(list)
        list.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(list.view)
        var top = view.topAnchor
        let leading = leadingAccessoryView()
        let trailing = accessoryView()
        if leading != nil || trailing != nil {
            // Thin control strip above the list: tabs on the left, sort on the right.
            let bar = NSStackView(views: [leading ?? NSView(), NSView(), trailing ?? NSView()])
            bar.orientation = .horizontal
            bar.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 10, right: 20)
            bar.alignment = .centerY
            bar.spacing = 12
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                // The content view runs under the unified title bar; the bar must not.
                bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            ])
            top = bar.bottomAnchor
        }
        NSLayoutConstraint.activate([
            list.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.view.topAnchor.constraint(equalTo: top),
            list.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        list.emptyState = emptyState
        list.listActions = listActions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coordinatorDidChange),
            name: CargoCoordinator.didChange,
            object: coordinator
        )
        reload()
    }

    @objc private func coordinatorDidChange() {
        reload()
    }

    func reload() {
        list.apply(sections())
        refreshAccessories()
    }

    // Subclass API
    var emptyState: EmptyState { EmptyState(symbol: page.symbolName, title: "Nothing here") }
    func sections() -> [ListSection] { [] }
    func listActions() -> [RowAction] { [refreshAction()] }
    /// Optional control shown right-aligned above the list.
    func accessoryView() -> NSView? { nil }
    /// Called after every reload so bar controls can enable/disable themselves.
    func refreshAccessories() {}

    func barButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        return button
    }

    func modernFilterSegments(labels: [String], action: Selector) -> NSSegmentedControl {
        let control = ModernPillControl(labels: labels, trackingMode: .selectOne, target: self, action: action)
        control.controlSize = .large
        control.segmentStyle = .capsule
        control.font = .systemFont(ofSize: 14, weight: .medium)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func modernFilterPopup(width: CGFloat? = nil, symbolName: String? = nil) -> NSPopUpButton {
        let popup = ModernPillPopupButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.bezelStyle = .rounded
        popup.focusRingType = .none
        popup.isBordered = false
        popup.font = .systemFont(ofSize: 14, weight: .medium)
        popup.widthAnchor.constraint(equalToConstant: width ?? 180).isActive = true
        if let symbolName {
            popup.image = Theme.symbol(symbolName, pointSize: 13, weight: .medium)
            popup.imagePosition = .imageLeading
        }
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)
        return popup
    }
    /// Optional control shown left-aligned above the list (tabs).
    func leadingAccessoryView() -> NSView? { nil }

    // MARK: - Shared helpers

    func refreshAction() -> RowAction {
        RowAction(title: "Refresh") { [weak self] in
            guard let self else { return }
            Task { _ = await self.coordinator.runBackgroundCycle() }
        }
    }

    func copyAction(_ title: String = "Copy Name", _ value: String) -> RowAction {
        RowAction(title: title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }

    func revealAction(_ path: String?) -> RowAction {
        RowAction(title: "Reveal in Finder", isEnabled: path.map { FileManager.default.fileExists(atPath: $0) } ?? false) {
            guard let path else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func confirm(_ message: String, detail: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func badge(for status: RemoteTransferStatus) -> StatusBadge {
        switch status {
        case .downloading: .info(status.displayName)
        case .seeding: .init(text: status.displayName, color: .systemTeal)
        case .completed: .success(status.displayName)
        case .failed: .failure(status.displayName)
        case .waiting, .cancelled, .unknown: .neutral(status.displayName)
        }
    }

    static func badge(for status: LocalSyncStatus) -> StatusBadge {
        switch status {
        case .queued: .neutral(status.displayName)
        case .downloading, .importing: .info(status.displayName)
        case .completed: .success(status.displayName)
        case .needsReview: .highlight("In Inbox")
        case .failed: .failure(status.displayName)
        }
    }
}

// MARK: - Transfers

final class TransfersPageViewController: PageViewController {
    override var emptyState: EmptyState {
        EmptyState(symbol: "arrow.down.circle", title: "No active transfers", detail: "Paste a magnet link with ⌘V or use the + button to add one.")
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Add Transfer…") { [weak self] in self?.addTransferFromPrompt() },
            RowAction(title: "Add Transfer from Clipboard") { [weak self] in self?.addTransferFromClipboard() },
            RowAction(title: "Clear Finished Transfers", isSeparatorBefore: true) { [weak self] in
                self?.run { try await self?.coordinator.cleanFinishedTransfers() }
            },
            RowAction(title: "Refresh", isSeparatorBefore: true) { [weak self] in
                guard let self else { return }
                Task { _ = await self.coordinator.runBackgroundCycle() }
            }
        ]
    }

    private lazy var clearFinishedButton = barButton("Clear Finished", action: #selector(clearFinished))

    override func accessoryView() -> NSView? { clearFinishedButton }

    override func refreshAccessories() {
        clearFinishedButton.isEnabled = coordinator.dashboardState.transfers.contains { [.completed, .seeding].contains($0.status) }
    }

    @objc private func clearFinished() {
        run { [weak self] in try await self?.coordinator.cleanFinishedTransfers() }
    }

    override func sections() -> [ListSection] {
        let state = coordinator.dashboardState
        let rows = state.transfers.map { transfer -> ListRow in
            let isActive = transfer.status == .downloading || transfer.status == .waiting
            let displayName = LibraryOrganizer.displayTitle(for: transfer.name)
            let posterURL = transfer.posterURL.flatMap(URL.init(string:))
                ?? LibraryOrganizer.posterURL(for: transfer.name, library: state.libraryItems, metadata: state.metadata)
            var actions: [RowAction] = []
            if transfer.status == .failed {
                actions.append(RowAction(title: "Retry") { [weak self] in
                    self?.run { try await self?.coordinator.retryTransfer(id: transfer.id) }
                })
            }
            actions.append(RowAction(
                title: isActive ? "Cancel Transfer" : "Remove Transfer",
                isDestructive: true,
                confirmation: .init(
                    message: "\(isActive ? "Cancel" : "Remove") “\(displayName)”?",
                    detail: isActive ? "The download stops and is removed from Put.io." : "Files already in Put.io are kept.",
                    button: isActive ? "Cancel Transfer" : "Remove",
                    pluralMessage: isActive ? "Cancel %d transfers?" : "Remove %d transfers?"
                )
            ) { [weak self] in
                self?.run { try await self?.coordinator.cancelTransfer(id: transfer.id) }
            })
            actions.append(copyAction("Copy Name", displayName))

            return ListRow(
                id: String(transfer.id),
                title: displayName,
                details: [
                    "\(Formatters.percent(transfer.progress)) · \(Formatters.bytes(transfer.sizeBytes))",
                    "\(isActive ? "Started" : "Transferred") \(Formatters.dateTime.string(from: transfer.updatedAt))"
                ],
                badge: Self.badge(for: transfer.status),
                progress: isActive ? transfer.progress : nil,
                thumbnail: posterURL,
                primaryAction: transfer.status == .failed ? actions.first : nil,
                menuActions: actions
            )
        }
        return [ListSection(rows: rows)]
    }

    func addTransferFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("magnet:") || value.hasPrefix("http") else {
            addTransferFromPrompt()
            return
        }
        run { [weak self] in try await self?.coordinator.addTransfer(url: value) }
    }

    func addTransferFromPrompt() {
        let alert = NSAlert()
        alert.messageText = "Add transfer to Put.io"
        alert.informativeText = "Magnet link or torrent / HTTP URL."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "magnet:?xt=…"
        if let clip = NSPasteboard.general.string(forType: .string), clip.hasPrefix("magnet:") || clip.hasPrefix("http") {
            field.stringValue = clip
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue
        run { [weak self] in try await self?.coordinator.addTransfer(url: value) }
    }
}

// MARK: - Discover

final class DiscoverPageViewController: PageViewController, NSSearchFieldDelegate {
    private enum CatalogTab: Int {
        case movies, series
    }

    private enum ViewMode: Int {
        case list, posters
    }

    private var catalogTab = CatalogTab.movies
    private var viewMode = ViewMode.posters
    private var catalogFilter = ""
    private var posterGridController: PosterGridViewController?
    private var detailController: DiscoverDetailViewController?

    private lazy var catalogControl: NSSegmentedControl = {
        let control = modernFilterSegments(labels: ["Top Movies", "Top Series"], action: #selector(catalogTabChanged(_:)))
        control.selectedSegment = catalogTab.rawValue
        return control
    }()

    private lazy var catalogFilterPopup: NSPopUpButton = {
        let popup = modernFilterPopup(width: 218, symbolName: "line.3.horizontal.decrease.circle")
        popup.target = self
        popup.action = #selector(catalogFilterChanged(_:))
        return popup
    }()

    private lazy var viewModeControl: NSSegmentedControl = {
        let control = modernFilterSegments(labels: ["List", "Posters"], action: #selector(viewModeChanged(_:)))
        control.selectedSegment = viewMode.rawValue
        return control
    }()

    private lazy var searchField: NSSearchField = {
        let field = NSSearchField()
        field.placeholderString = "Search Chill…"
        field.controlSize = .large
        field.font = .systemFont(ofSize: 13)
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true
        field.target = self
        field.action = #selector(search)
        field.delegate = self
        return field
    }()
    private lazy var searchButton = barButton("Search", action: #selector(search))

    override var subtitle: String {
        coordinator.dashboardChillSearchQuery.isEmpty ? coordinator.dashboardChillCatalogStatus : coordinator.dashboardChillSearchStatus
    }

    override var emptyState: EmptyState {
        if !coordinator.dashboardIsChillConnected {
            return EmptyState(
                symbol: "sparkles",
                title: "Connect Chill to discover releases",
                detail: "Add your Chill token in Settings → Chill."
            )
        }
        if coordinator.dashboardChillSearchQuery.isEmpty {
            let loading = coordinator.dashboardChillCatalogStatus.hasPrefix("Loading")
            return EmptyState(
                symbol: "sparkles",
                title: loading ? "Loading top movies and series" : "No top titles available",
                detail: loading ? coordinator.dashboardChillCatalogStatus : "Refresh the list or search by movie, show, or episode."
            )
        }
        return EmptyState(symbol: "sparkles", title: "No Chill results", detail: coordinator.dashboardChillSearchStatus)
    }

    override func leadingAccessoryView() -> NSView? {
        let stack = NSStackView(views: [catalogControl, catalogFilterPopup, searchField, searchButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    override func accessoryView() -> NSView? {
        viewModeControl
    }

    override func refreshAccessories() {
        if searchField.currentEditor() == nil {
            searchField.stringValue = coordinator.dashboardChillSearchQuery
        }
        catalogControl.selectedSegment = catalogTab.rawValue
        searchButton.isEnabled = coordinator.dashboardIsChillConnected && !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showingCatalog = coordinator.dashboardChillSearchQuery.isEmpty
        catalogFilterPopup.isHidden = !showingCatalog
        viewModeControl.isHidden = !showingCatalog
        viewModeControl.selectedSegment = viewMode.rawValue
        updateFilterMenu()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let grid = PosterGridViewController()
        posterGridController = grid
        addChild(grid)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid.view)
        NSLayoutConstraint.activate([
            grid.view.leadingAnchor.constraint(equalTo: list.view.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: list.view.trailingAnchor),
            grid.view.topAnchor.constraint(equalTo: list.view.topAnchor),
            grid.view.bottomAnchor.constraint(equalTo: list.view.bottomAnchor)
        ])
        reload()
        if coordinator.dashboardIsChillConnected {
            Task { await coordinator.refreshChillCatalog() }
        } else if coordinator.dashboardChillStatus.hasPrefix("Token saved") {
            Task { await coordinator.verifyChillConnection() }
        }
    }

    override func reload() {
        guard let posterGridController else {
            super.reload()
            return
        }

        // Only render the presentation that is currently active. Rebuilding
        // both controls on every coordinator notification makes the hidden
        // view invalidate its layout while the visible view is being swapped,
        // which is the source of the poster/list flash.
        let showingGrid = coordinator.dashboardChillSearchQuery.isEmpty && viewMode == .posters
        list.emptyState = emptyState
        posterGridController.emptyState = emptyState
        if showingGrid {
            posterGridController.apply(catalogRows())
        } else {
            list.apply(sections())
        }
        refreshAccessories()
        updateCatalogPresentation()
    }

    private func updateCatalogPresentation() {
        guard let posterGridController else { return }
        if detailController != nil {
            setHidden(true, for: list.view)
            setHidden(true, for: posterGridController.view)
            return
        }
        let showingGrid = coordinator.dashboardChillSearchQuery.isEmpty && viewMode == .posters
        setHidden(showingGrid, for: list.view)
        setHidden(!showingGrid, for: posterGridController.view)
    }

    private func setHidden(_ hidden: Bool, for view: NSView) {
        guard view.isHidden != hidden else { return }
        view.isHidden = hidden
    }

    private func showDetail(_ title: DiscoverTitle, onSend: (() -> Void)? = nil) {
        guard detailController == nil else { return }
        let detail = DiscoverDetailViewController(
            seed: title,
            coordinator: coordinator,
            onBack: { [weak self] in self?.hideDetail() },
            onSend: onSend
        )
        detailController = detail
        addChild(detail)
        detail.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(detail.view)
        NSLayoutConstraint.activate([
            detail.view.leadingAnchor.constraint(equalTo: list.view.leadingAnchor),
            detail.view.trailingAnchor.constraint(equalTo: list.view.trailingAnchor),
            detail.view.topAnchor.constraint(equalTo: list.view.topAnchor),
            detail.view.bottomAnchor.constraint(equalTo: list.view.bottomAnchor)
        ])
        updateCatalogPresentation()
    }

    private func hideDetail() {
        guard let detail = detailController else { return }
        detail.view.removeFromSuperview()
        detail.removeFromParent()
        detailController = nil
        updateCatalogPresentation()
    }

    private func movieTitle(_ movie: ChillMovie) -> DiscoverTitle {
        DiscoverTitle(
            id: movie.id,
            title: movie.title,
            year: movie.year > 0 ? movie.year : nil,
            kind: .movie,
            posterURL: movie.posterLink,
            overview: movie.overview.isEmpty ? nil : movie.overview,
            rating: movie.rating > 0 ? movie.rating : nil,
            genres: movie.genres,
            networks: [],
            imdbID: Self.imdbID(from: movie.externalLink),
            externalURL: movie.externalLink,
            searchQuery: movie.year > 0 ? movie.displayTitle + " " + String(movie.year) : movie.displayTitle
        )
    }

    private func showTitle(_ show: ChillTVShow) -> DiscoverTitle {
        DiscoverTitle(
            id: show.id,
            title: show.title,
            year: show.year > 0 ? show.year : nil,
            kind: .series,
            posterURL: show.posterLink,
            overview: show.overview.isEmpty ? nil : show.overview,
            rating: show.rating > 0 ? show.rating : nil,
            genres: [],
            networks: show.networks,
            imdbID: show.imdbID.isEmpty ? nil : show.imdbID,
            externalURL: show.externalLink,
            searchQuery: show.year > 0 ? show.title + " " + String(show.year) : show.title
        )
    }

    private static func imdbID(from url: URL?) -> String? {
        guard let value = url?.absoluteString,
              let range = value.range(of: "tt[0-9]+", options: .regularExpression)
        else { return nil }
        return String(value[range])
    }

    private func catalogRows() -> [ListRow] {
        guard coordinator.dashboardChillSearchQuery.isEmpty else { return [] }
        return catalogTab == .movies ? movieCatalogSection().rows : seriesCatalogSection().rows
    }

    private func updateFilterMenu() {
        let current = catalogFilter
        let lists: [String]
        let genres: [String]
        let allTitle: String
        if catalogTab == .movies {
            allTitle = "All Lists & Genres"
            lists = Set(coordinator.dashboardChillCatalogMovies.compactMap { $0.source?.displayName }).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            genres = Set(coordinator.dashboardChillCatalogMovies.flatMap(\.genres)).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        } else {
            allTitle = "All Lists"
            let providers = coordinator.dashboardChillCatalogShows.compactMap { $0.source?.displayName }
            lists = Set(providers.isEmpty ? coordinator.dashboardChillCatalogShows.flatMap(\.networks) : providers).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            genres = []
        }

        let menu = NSMenu()
        let allItem = NSMenuItem(title: allTitle, action: nil, keyEquivalent: "")
        allItem.representedObject = ""
        menu.addItem(allItem)

        func addSection(_ title: String, options: [String]) {
            guard !options.isEmpty else { return }
            if menu.items.count > 1 { menu.addItem(.separator()) }
            let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for option in options {
                let item = NSMenuItem(title: option, action: nil, keyEquivalent: "")
                item.representedObject = option
                menu.addItem(item)
            }
        }

        addSection("Lists", options: lists)
        addSection("Genres", options: genres)
        catalogFilterPopup.menu = menu

        let available = lists + genres
        if available.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            catalogFilter = available.first { $0.caseInsensitiveCompare(current) == .orderedSame } ?? current
            catalogFilterPopup.selectItem(withTitle: catalogFilter)
        } else {
            catalogFilter = ""
            catalogFilterPopup.selectItem(at: 0)
        }
    }

    private func matchesCatalogFilter(_ values: [String]) -> Bool {
        catalogFilter.isEmpty || values.contains { $0.caseInsensitiveCompare(catalogFilter) == .orderedSame }
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Search") { [weak self] in self?.search() },
            RowAction(title: "Open Chill in Browser") {
                NSWorkspace.shared.open(URL(string: "https://chill.institute/search")!)
            },
            RowAction(title: "Refresh Top List", isEnabled: coordinator.dashboardIsChillConnected) { [weak self] in
                guard let self else { return }
                Task { await self.coordinator.refreshChillCatalog() }
            },
            RowAction(title: "Refresh Results", isEnabled: !coordinator.dashboardChillSearchQuery.isEmpty) { [weak self] in
                guard let self else { return }
                Task { await self.coordinator.searchChill(query: self.coordinator.dashboardChillSearchQuery) }
            }
        ]
    }

    override func sections() -> [ListSection] {
        if coordinator.dashboardChillSearchQuery.isEmpty {
            return [catalogTab == .movies ? movieCatalogSection() : seriesCatalogSection()]
        }

        let rows = coordinator.dashboardChillSearchResults.map { result -> ListRow in
            let canSend = coordinator.dashboardIsChillConnected && coordinator.dashboardIsConnected && !result.link.isEmpty
            let send = RowAction(
                title: "Send to Put.io",
                isEnabled: canSend,
                confirmation: .init(
                    message: "Send “\(result.releaseTitle)” to Put.io?",
                    detail: "Chill supplies the release link; Cargo will then use its normal Put.io → Inbox → Library pipeline.",
                    button: "Send"
                )
            ) { [weak self] in
                guard let self else { return }
                self.run { try await self.coordinator.sendChillResult(result) }
            }
            let open = RowAction(title: "Open Release Link", isEnabled: !result.link.isEmpty) {
                guard let url = URL(string: result.link) else { return }
                NSWorkspace.shared.open(url)
            }
            let kind: DiscoverTitle.Kind = (result.releaseInfo?.season != nil || result.releaseInfo?.episode != nil) ? .series : .movie
            let title = result.releaseTitle
            let year = result.releaseInfo?.year
            let detail = RowAction(title: "View Details") { [weak self] in
                guard let self else { return }
                let seed = DiscoverTitle(
                    id: result.id,
                    title: title,
                    year: year,
                    kind: kind,
                    posterURL: nil,
                    overview: nil,
                    rating: nil,
                    genres: [],
                    networks: [],
                    imdbID: result.imdbID,
                    externalURL: nil,
                    searchQuery: year.map { "\(title) \($0)" } ?? title
                )
                self.showDetail(seed, onSend: canSend ? { send.handler() } : nil)
            }
            let copyLink = copyAction("Copy Link", result.link)
            let details = [result.indexer, result.displayTraits].filter { !$0.isEmpty }.joined(separator: " · ")
            return ListRow(
                id: result.id,
                title: result.releaseTitle,
                details: [details, result.title == result.releaseTitle ? nil : result.title].compactMap { $0 }.filter { !$0.isEmpty },
                badge: result.seeders > 0 ? .success("\(result.seeders) seeders") : .neutral("No seeders"),
                primaryAction: detail,
                menuActions: [detail, send, open, copyLink]
            )
        }
        return [ListSection(rows: rows)]
    }

    private func movieCatalogSection() -> ListSection {
        let rows = coordinator.dashboardChillCatalogMovies.filter { movie in
            let values = [movie.source?.displayName].compactMap { $0 } + movie.genres
            return matchesCatalogFilter(values)
        }.map { movie -> ListRow in
            let query = movie.year > 0 ? "\(movie.displayTitle) \(movie.year)" : movie.displayTitle
            let search = RowAction(title: "Search Releases") { [weak self] in
                self?.coordinator.requestChillSearch(query: query)
            }
            let send = RowAction(
                title: "Send to Put.io",
                isEnabled: coordinator.dashboardIsChillConnected && coordinator.dashboardIsConnected && !movie.link.isEmpty,
                confirmation: .init(
                    message: "Send “\(movie.displayTitle)” to Put.io?",
                    detail: "This catalog movie has a direct Chill link; Cargo will use the normal Put.io → Inbox → Library pipeline.",
                    button: "Send"
                )
            ) { [weak self] in
                guard let self else { return }
                self.run { try await self.coordinator.sendChillMovie(movie) }
            }
            var menu = [search, send]
            let openDetail = RowAction(title: "View Details") { [weak self] in
                guard let self else { return }
                self.showDetail(self.movieTitle(movie), onSend: { send.handler() })
            }
            if let externalLink = movie.externalLink {
                menu.append(RowAction(title: "Open Movie Details") { NSWorkspace.shared.open(externalLink) })
            }
            menu.append(copyAction("Copy Title", movie.displayTitle))
            let genreText = movie.genres.joined(separator: ", ")
            return ListRow(
                id: movie.id,
                title: movie.displayTitle,
                details: [movie.displayTraits, genreText].filter { !$0.isEmpty },
                badge: movie.seeders > 0 ? .success("\(movie.seeders) seeders") : .neutral("No seeders"),
                thumbnail: movie.posterLink,
                primaryAction: openDetail,
                menuActions: [openDetail] + menu
            )
        }
        return ListSection(title: "Top Movies", rows: rows)
    }

    private func seriesCatalogSection() -> ListSection {
        let rows = coordinator.dashboardChillCatalogShows.filter { show in
            let values = [show.source?.displayName].compactMap { $0 } + show.networks
            return matchesCatalogFilter(values)
        }.map { show -> ListRow in
            let query = show.year > 0 ? "\(show.title) \(show.year)" : show.title
            let search = RowAction(title: "Search Releases") { [weak self] in
                self?.coordinator.requestChillSearch(query: query)
            }
            let openDetail = RowAction(title: "View Details") { [weak self] in
                guard let self else { return }
                self.showDetail(self.showTitle(show))
            }
            var menu = [openDetail, search]
            if let externalLink = show.externalLink {
                menu.append(RowAction(title: "Open Series Details") { NSWorkspace.shared.open(externalLink) })
            }
            menu.append(copyAction("Copy Title", show.title))
            let networks = show.networks.joined(separator: ", ")
            let status: StatusBadge? = show.statusLabel.isEmpty ? nil : .neutral(show.statusLabel)
            return ListRow(
                id: show.id,
                title: show.year > 0 ? "\(show.title) (\(show.year))" : show.title,
                details: [show.displayTraits, networks].filter { !$0.isEmpty },
                badge: status,
                thumbnail: show.posterLink,
                primaryAction: openDetail,
                menuActions: menu
            )
        }
        return ListSection(title: "Top Series", rows: rows)
    }

    @objc private func catalogTabChanged(_ sender: NSSegmentedControl) {
        catalogTab = CatalogTab(rawValue: sender.selectedSegment) ?? .movies
        catalogFilter = ""
        reload()
    }

    @objc private func catalogFilterChanged(_ sender: NSPopUpButton) {
        catalogFilter = sender.selectedItem?.representedObject as? String ?? ""
        reload()
    }

    @objc private func viewModeChanged(_ sender: NSSegmentedControl) {
        viewMode = ViewMode(rawValue: sender.selectedSegment) ?? .list
        reload()
    }

    @objc private func search() {
        Task { await coordinator.searchChill(query: searchField.stringValue) }
    }
}

// MARK: - Files

final class FilesPageViewController: PageViewController {
    override var emptyState: EmptyState {
        EmptyState(symbol: "folder", title: "No video files in Put.io", detail: coordinator.dashboardIsConnected ? nil : coordinator.dashboardPutIOStatus)
    }

    override func sections() -> [ListSection] {
        let state = coordinator.dashboardState
        let rows = state.remoteMediaFiles.map { file -> ListRow in
            let job = state.localJobs
                .filter { $0.remoteFileID == file.id }
                .max { $0.updatedAt < $1.updatedAt }
            let deleted = state.deletedRemoteFileIDs.contains(file.id)

            let badge: StatusBadge? = if deleted {
                .neutral("Deleted")
            } else if let job {
                Self.badge(for: job.status)
            } else {
                nil
            }

            let syncTitle: String = switch job?.status {
            case nil: "Sync"
            case .queued: "Queued"
            case .downloading: "Downloading…"
            case .importing: "Importing…"
            case .needsReview: "In Inbox"
            case .completed: "Downloaded"
            case .failed: "Retry"
            }
            let canSync = !deleted && (job == nil || job?.status == .failed)
            let sync = RowAction(title: syncTitle, isEnabled: canSync) { [weak self] in
                guard let self else { return }
                if coordinator.isRemoteClientMode {
                    self.run { try await self.coordinator.executeRemoteCommand(.enqueueLocalSync(remoteFileID: file.id)) }
                } else {
                    coordinator.enqueueLocalSync(remoteFileID: file.id)
                    Task { await self.coordinator.processLocalSync(remoteFileID: file.id) }
                }
            }
            let delete = RowAction(
                title: "Delete from Put.io…",
                isDestructive: true,
                isEnabled: !deleted,
                isSeparatorBefore: true,
                confirmation: .init(
                    message: "Delete “\(file.displayPath)” from Put.io?",
                    detail: "It goes to Put.io's trash; empty the trash in Settings → Put.io to free the space. Local copies are not affected.",
                    button: "Delete",
                    pluralMessage: "Delete %d files from Put.io?"
                )
            ) { [weak self] in
                self?.run { try await self?.coordinator.deleteRemoteFile(remoteFileID: file.id) }
            }
            let subtitles = RowAction(title: "Download Subtitles…", isEnabled: !deleted && !coordinator.isRemoteClientMode) { [weak self] in
                self?.chooseSubtitle(for: file)
            }
            let copyLink = RowAction(title: "Copy Download Link", isEnabled: !deleted && !coordinator.isRemoteClientMode) { [weak self] in
                self?.run {
                    guard let url = try await self?.coordinator.downloadURL(remoteFileID: file.id) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }

            return ListRow(
                id: String(file.id),
                title: file.displayPath,
                details: [
                    "\(file.type.displayName) · \(Formatters.bytes(file.sizeBytes))",
                    job?.errorMessage
                ].compactMap { $0 },
                badge: badge,
                progress: job.map { $0.status == .downloading ? $0.progress : nil } ?? nil,
                primaryAction: sync,
                menuActions: [
                    sync,
                    subtitles,
                    copyLink,
                    revealAction(job?.destination),
                    copyAction("Copy Name", file.name),
                    delete
                ]
            )
        }
        let archives = state.remoteArchiveFiles.map { archive -> ListRow in
            let requested = state.requestedExtractionFileIDs.contains(archive.id)
            let extract = RowAction(title: requested ? "Extracting…" : "Extract on Put.io", isEnabled: !requested) { [weak self] in
                self?.run { try await self?.coordinator.requestExtraction(remoteFileID: archive.id) }
            }
            let delete = RowAction(
                title: "Delete from Put.io…",
                isDestructive: true,
                isSeparatorBefore: true,
                confirmation: .init(
                    message: "Delete “\(archive.displayPath)” from Put.io?",
                    detail: "It goes to Put.io's trash; empty the trash in Settings → Put.io to free the space.",
                    button: "Delete",
                    pluralMessage: "Delete %d files from Put.io?"
                )
            ) { [weak self] in
                self?.run { try await self?.coordinator.deleteRemoteFile(remoteFileID: archive.id) }
            }
            return ListRow(
                id: "archive-\(archive.id)",
                title: archive.displayPath,
                details: ["Archive · \(Formatters.bytes(archive.sizeBytes))"],
                badge: requested ? .info("Extracting") : .warning("Archive"),
                primaryAction: extract,
                menuActions: [extract, copyAction("Copy Name", archive.name), delete]
            )
        }
        var sections = [ListSection(rows: rows)]
        if !archives.isEmpty {
            sections.append(ListSection(title: "Archives — Put.io unpacks these server-side", rows: archives))
        }
        return sections
    }

    private func chooseSubtitle(for file: RemoteFile) {
        run { [weak self] in
            guard let self else { return }
            let subtitles = try await coordinator.fetchSubtitles(remoteFileID: file.id)
            guard !subtitles.isEmpty else {
                let alert = NSAlert()
                alert.messageText = "No subtitles on Put.io"
                alert.informativeText = "Put.io has no subtitles for “\(file.name)”."
                alert.runModal()
                return
            }
            let alert = NSAlert()
            alert.messageText = "Download subtitle"
            alert.informativeText = "Saved as an .srt next to the local copy (or in the staging folder)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
            for subtitle in subtitles {
                popup.addItem(withTitle: "\(subtitle.language) · \(subtitle.name)\(subtitle.source.isEmpty ? "" : " (\(subtitle.source))")")
            }
            alert.accessoryView = popup
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let chosen = subtitles[max(0, popup.indexOfSelectedItem)]
            let url = try await coordinator.downloadSubtitle(chosen, remoteFileID: file.id)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Inbox

final class InboxPageViewController: PageViewController {
    private struct InboxEntry {
        let sourceURL: URL
        let job: LocalSyncJob?
        var name: String { job?.name ?? sourceURL.lastPathComponent }
    }

    override var emptyState: EmptyState {
        EmptyState(
            symbol: "tray",
            title: "Nothing waiting for organization",
            detail: coordinator.isRemoteClientMode
                ? "Downloads and organization happen on the resident Cargo Mac."
                : "Synced files land in \(coordinator.state.settings.stagingDirectoryName) and show up here."
        )
    }

    private lazy var clearFailedButton = barButton("Clear Failed", action: #selector(clearFailed))

    override func accessoryView() -> NSView? { clearFailedButton }

    override func refreshAccessories() {
        clearFailedButton.isEnabled = coordinator.dashboardState.localJobs.contains { $0.status == .failed }
    }

    @objc private func clearFailed() {
        coordinator.clearFailedJobs()
    }

    override func listActions() -> [RowAction] {
        let inbox = coordinator.isRemoteClientMode ? nil : coordinator.libraryRootURL()?
            .appendingPathComponent(coordinator.state.settings.stagingDirectoryName, isDirectory: true)
        return [
            RowAction(title: "Open Inbox in Finder", isEnabled: inbox != nil) {
                guard let inbox else { return }
                NSWorkspace.shared.open(inbox)
            },
            RowAction(title: "Clear Failed", isEnabled: coordinator.dashboardState.localJobs.contains { $0.status == .failed }) { [weak self] in
                self?.coordinator.clearFailedJobs()
            },
            refreshAction()
        ]
    }

    override func sections() -> [ListSection] {
        let state = coordinator.dashboardState

        let downloading = state.localJobs
            .filter { coordinator.isRemoteClientMode ? $0.status != .completed : [.queued, .downloading, .importing, .failed].contains($0.status) }
            .map { job in
                let displayName = LibraryOrganizer.displayTitle(for: job.name)
                return ListRow(
                    id: job.id.uuidString,
                    title: displayName,
                    details: [job.destination ?? "Destination not chosen", job.errorMessage].compactMap { $0 },
                    badge: Self.badge(for: job.status),
                    progress: job.status == .downloading ? job.progress : nil,
                    thumbnail: job.posterURL.flatMap(URL.init(string:))
                        ?? LibraryOrganizer.posterURL(for: job.name, library: state.libraryItems, metadata: state.metadata),
                    menuActions: [copyAction("Copy Name", displayName), revealAction(job.destination)]
                )
            }

        if coordinator.isRemoteClientMode {
            return [ListSection(title: "Resident downloads", rows: downloading)]
        }

        let pendingByDestination = state.localJobs
            .filter { $0.status == .needsReview }
            .reduce(into: [String: LocalSyncJob]()) { result, job in
                if let destination = job.destination { result[destination] = job }
            }
        let inbox = coordinator.inboxFileURLs()
            .map { InboxEntry(sourceURL: $0, job: pendingByDestination[$0.path]) }
            .map { entry -> ListRow in
                let exists = FileManager.default.fileExists(atPath: entry.sourceURL.path)
                let preview = LibraryOrganizer.preview(for: entry.name, settings: state.settings)
                let destination = preview.relativePath.map { relative in
                    state.settings.libraryRootPath.map {
                        URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(relative).path
                    } ?? relative
                }

                let organize = RowAction(title: "Organize", isEnabled: exists && destination != nil) { [weak self] in
                    self?.organize(entry: entry)
                }
                let badge: StatusBadge = if !exists {
                    .failure("Missing")
                } else if destination == nil {
                    .warning("Review")
                } else {
                    .highlight(preview.kind.displayName)
                }
                return ListRow(
                    id: entry.sourceURL.path,
                    title: LibraryOrganizer.displayTitle(for: entry.name),
                    details: [
                        destination.map { "→ \($0)" } ?? "Review manually · \(preview.explanation)",
                        entry.job == nil ? "Not tracked by Cargo" : nil
                    ].compactMap { $0 },
                    badge: badge,
                    thumbnail: LibraryOrganizer.posterURL(
                        for: entry.name,
                        library: state.libraryItems,
                        metadata: state.metadata
                    ),
                    primaryAction: organize,
                    menuActions: [
                        organize,
                        revealAction(entry.sourceURL.path),
                        copyAction("Copy Path", entry.sourceURL.path),
                        RowAction(
                            title: "Move to Trash",
                            isDestructive: true,
                            isEnabled: exists,
                            isSeparatorBefore: true,
                            confirmation: .init(message: "Move “\(entry.name)” to Trash?", detail: "The file is removed from the Inbox.", button: "Move to Trash", pluralMessage: "Move %d files to Trash?")
                        ) { [weak self] in
                            guard let self else { return }
                            run { try FileManager.default.trashItem(at: entry.sourceURL, resultingItemURL: nil) }
                            reload()
                        }
                    ]
                )
            }

        let organized = state.localJobs
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(10)
            .map { job in
                let displayName = LibraryOrganizer.displayTitle(for: job.name)
                return ListRow(
                    id: "organized-\(job.id.uuidString)",
                    title: displayName,
                    details: [job.destination ?? "Destination unavailable"],
                    badge: .success("Organized"),
                    thumbnail: job.posterURL.flatMap(URL.init(string:))
                        ?? LibraryOrganizer.posterURL(for: job.name, library: state.libraryItems, metadata: state.metadata),
                    menuActions: [revealAction(job.destination), copyAction("Copy Name", displayName)]
                )
            }

        return [
            ListSection(title: "Downloading to \(state.settings.stagingDirectoryName)", rows: downloading),
            ListSection(title: inbox.isEmpty ? nil : "Waiting for organization", rows: inbox),
            ListSection(title: "Recently organized", rows: Array(organized))
        ]
    }

    private func organize(entry: InboxEntry) {
        run { [weak self] in
            guard let self else { return }
            if let job = entry.job {
                try coordinator.organizeLocalJob(jobID: job.id)
            } else {
                try coordinator.organizeInboxFile(at: entry.sourceURL)
            }
        }
    }
}

// MARK: - Watchlist

final class WatchlistPageViewController: PageViewController {
    private enum ViewMode: Int {
        case list, posters
    }

    private var viewMode = ViewMode.posters
    private var posterGridController: PosterGridViewController?
    private var searchQuery = ""

    private lazy var clearSearchButton: NSButton = {
        let button = NSButton(image: Theme.symbol("xmark.circle.fill", pointSize: 15, weight: .medium) ?? NSImage(), target: self, action: #selector(clearSearch))
        button.isBordered = false
        button.toolTip = "Clear search"
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }()

    private lazy var viewModeControl: NSSegmentedControl = {
        let control = modernFilterSegments(labels: ["List", "Posters"], action: #selector(viewModeChanged(_:)))
        control.selectedSegment = viewMode.rawValue
        return control
    }()

    enum Sort: String, CaseIterable {
        case added, year, title, status
        var label: String {
            switch self {
            case .added: "Recently Added"
            case .year: "Year"
            case .title: "Title"
            case .status: "Status"
            }
        }
        static let defaultsKey = "cargo.watchlist.sort"
    }

    private var sort: Sort = Sort(rawValue: UserDefaults.standard.string(forKey: Sort.defaultsKey) ?? "") ?? .added {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Sort.defaultsKey)
            reload()
        }
    }

    /// The tabs above the list, by where a title is in the pipeline.
    enum Filter: Int, CaseIterable {
        case all, wanted, onPutIO, inLibrary
        var label: String {
            switch self {
            case .all: "All"
            case .wanted: "Wanted"
            case .onPutIO: "On Put.io"
            case .inLibrary: "In Library"
            }
        }
        static let defaultsKey = "cargo.watchlist.tab"
    }

    private var filter: Filter = Filter(rawValue: UserDefaults.standard.integer(forKey: Filter.defaultsKey)) ?? .all {
        didSet {
            UserDefaults.standard.set(filter.rawValue, forKey: Filter.defaultsKey)
            reload()
        }
    }

    override func leadingAccessoryView() -> NSView? {
        let control = modernFilterSegments(labels: Filter.allCases.map(\.label), action: #selector(filterChanged(_:)))
        control.selectedSegment = filter.rawValue
        let stack = NSStackView(views: [clearSearchButton, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        clearSearchButton.isHidden = searchQuery.isEmpty
        return stack
    }

    override func accessoryView() -> NSView? {
        let stack = NSStackView(views: [viewModeControl, sortPopup()])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    override func refreshAccessories() {
        viewModeControl.selectedSegment = viewMode.rawValue
        clearSearchButton.isHidden = searchQuery.isEmpty
    }

    @objc private func clearSearch() {
        searchQuery = ""
        reload()
    }

    func focusSearchResult(id: String) {
        guard let item = coordinator.dashboardState.imdbWatchlistItems.first(where: { $0.id == id }) else { return }
        if filter != .all { filter = .all }
        searchQuery = item.title
        reload()
    }

    func openSearchResult(id: String) {
        guard let item = coordinator.dashboardState.imdbWatchlistItems.first(where: { $0.id == id }) else { return }
        guard item.id.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(item.id)/") else {
            focusSearchResult(id: id)
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filter = Filter(rawValue: sender.selectedSegment) ?? .all
    }

    private func sortPopup() -> NSPopUpButton {
        let popup = modernFilterPopup(symbolName: "arrow.up.arrow.down")
        for option in Sort.allCases {
            popup.addItem(withTitle: "Sort by \(option.label)")
            popup.lastItem?.representedObject = option.rawValue
        }
        popup.selectItem(at: Sort.allCases.firstIndex(of: sort) ?? 0)
        popup.target = self
        popup.action = #selector(sortChanged(_:))
        return popup
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let next = Sort(rawValue: raw) else { return }
        sort = next
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let grid = PosterGridViewController()
        posterGridController = grid
        addChild(grid)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid.view)
        NSLayoutConstraint.activate([
            grid.view.leadingAnchor.constraint(equalTo: list.view.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: list.view.trailingAnchor),
            grid.view.topAnchor.constraint(equalTo: list.view.topAnchor),
            grid.view.bottomAnchor.constraint(equalTo: list.view.bottomAnchor)
        ])
        reload()
    }

    override func reload() {
        guard let posterGridController else {
            super.reload()
            return
        }

        let showingGrid = viewMode == .posters
        list.emptyState = emptyState
        posterGridController.emptyState = emptyState
        if showingGrid {
            posterGridController.apply(posterRows())
        } else {
            list.apply(sections())
        }
        refreshAccessories()
        updateWatchlistPresentation()
    }

    private func posterRows() -> [ListRow] {
        sections().flatMap(\.rows)
    }

    private func updateWatchlistPresentation() {
        guard let posterGridController else { return }
        let showingGrid = viewMode == .posters
        setHidden(showingGrid, for: list.view)
        setHidden(!showingGrid, for: posterGridController.view)
    }

    private func setHidden(_ hidden: Bool, for view: NSView) {
        guard view.isHidden != hidden else { return }
        view.isHidden = hidden
    }

    @objc private func viewModeChanged(_ sender: NSSegmentedControl) {
        viewMode = ViewMode(rawValue: sender.selectedSegment) ?? .list
        reload()
    }

    private func sorted(_ items: [IMDbWatchlistItem], state: CargoState) -> [IMDbWatchlistItem] {
        let byTitle: (IMDbWatchlistItem, IMDbWatchlistItem) -> Bool = {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        switch sort {
        case .added:
            // Newest first, as IMDb shows it; undated items last.
            return items.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .year:
            return items.sorted { ($0.year ?? 0, $1.title) > ($1.year ?? 0, $0.title) }
        case .title:
            return items.sorted(by: byTitle)
        case .status:
            let rank = ["Wanted": 0, "Available": 1, "Queued": 2, "In Inbox": 3, "Organized": 4]
            return items.sorted {
                let a = rank[Self.status(for: $0, state: state).text] ?? 9
                let b = rank[Self.status(for: $1, state: state).text] ?? 9
                return a == b ? byTitle($0, $1) : a < b
            }
        }
    }

    override var subtitle: String {
        let state = coordinator.dashboardState
        guard !state.imdbWatchlistItems.isEmpty else { return coordinator.dashboardWatchlistStatus }
        let counts = state.imdbWatchlistItems.reduce(into: [String: Int]()) { counts, item in
            counts[Self.status(for: item, state: state).text, default: 0] += 1
        }
        let parts = ["Organized", "In Inbox", "Available", "Wanted"].compactMap { key -> String? in
            guard let count = counts[key], count > 0 else { return nil }
            return "\(count) \(key.lowercased())"
        }
        return parts.joined(separator: " · ")
    }

    override var emptyState: EmptyState {
        EmptyState(symbol: "star", title: "No Watchlist titles yet", detail: coordinator.dashboardWatchlistStatus)
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Refresh Watchlist") { [weak self] in
                guard let self else { return }
                Task { _ = await self.coordinator.refreshIMDbWatchlist() }
            },
            RowAction(title: "Open Watchlist on IMDb") { [weak self] in
                guard let self, let url = URL(string: coordinator.state.settings.imdbWatchlistURL) else { return }
                NSWorkspace.shared.open(url)
            }
        ]
    }

    override func sections() -> [ListSection] {
        let state = coordinator.dashboardState
        let visible = state.imdbWatchlistItems.filter { item in
            let matchesSearch = searchQuery.isEmpty || Self.matchesSearch(searchQuery, item: item)
            let status = Self.status(for: item, state: state).text
            switch filter {
            case .all: return matchesSearch
            case .wanted: return matchesSearch && status == "Wanted"
            case .onPutIO: return matchesSearch && ["Available", "Queued", "In Inbox"].contains(status)
            case .inLibrary: return matchesSearch && status == "Organized"
            }
        }
        let rows = sorted(visible, state: state).map { item -> ListRow in
            let chillQuery = item.year.map { "\(item.title) \($0)" } ?? item.title
            let search = RowAction(title: "Search in Cargo") {
                self.coordinator.requestChillSearch(query: chillQuery)
            }
            let browserSearch = RowAction(title: "Open Chill in Browser") {
                var components = URLComponents(string: "https://chill.institute/search")
                components?.queryItems = [URLQueryItem(name: "q", value: chillQuery)]
                if let url = components?.url { NSWorkspace.shared.open(url) }
            }
            let imdb = RowAction(title: "Open on IMDb", isEnabled: item.id.hasPrefix("tt")) {
                if let url = URL(string: "https://www.imdb.com/title/\(item.id)/") { NSWorkspace.shared.open(url) }
            }
            let added = item.addedAt.map { "Added \(Formatters.date.string(from: $0))" } ?? item.id
            let meta = state.metadata[item.id]
            var menu = [search, browserSearch, imdb]
            if let meta {
                menu.append(RowAction(title: "Open on TMDB") { NSWorkspace.shared.open(meta.pageURL) })
            }
            if let library = Self.libraryItem(for: item, state: state), let root = coordinator.libraryRootURL() {
                menu.append(RowAction(title: "Reveal in Library") {
                    NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(library.relativePath)])
                })
            }
            menu.append(copyAction("Copy Title", item.title))
            return ListRow(
                id: item.id,
                title: item.year.map { "\(item.title) (\($0))" } ?? item.title,
                details: [[item.titleType, added].compactMap { $0 }.joined(separator: " · ")],
                badge: Self.status(for: item, state: state),
                thumbnail: meta?.posterURL,
                primaryAction: search,
                menuActions: menu
            )
        }
        return [ListSection(rows: rows)]
    }

    static func status(for item: IMDbWatchlistItem, state: CargoState) -> StatusBadge {
        if libraryItem(for: item, state: state) != nil { return .success("Organized") }
        let matching = state.localJobs.filter { matches(item.title, filename: $0.name) }
        if matching.contains(where: { $0.status == .completed }) { return .success("Organized") }
        if matching.contains(where: { $0.status == .needsReview }) { return .highlight("In Inbox") }
        if matching.contains(where: { [.queued, .downloading, .importing].contains($0.status) }) { return .info("Queued") }
        if state.remoteMediaFiles.contains(where: { matches(item.title, filename: $0.displayPath) }) { return .info("Available") }
        return .warning("Wanted")
    }

    /// Same rule as `CargoCoordinator.libraryItem(for:)`, usable without an instance.
    static func libraryItem(for item: IMDbWatchlistItem, state: CargoState) -> LibraryItem? {
        if let meta = state.metadata[item.id],
           let hit = state.libraryItems.first(where: { state.metadata[$0.id]?.tmdbID == meta.tmdbID }) {
            return hit
        }
        let wanted = CargoCoordinator.normalizedTitle(item.title)
        return state.libraryItems.first {
            CargoCoordinator.normalizedTitle($0.title) == wanted && (item.year == nil || $0.year == nil || $0.year == item.year)
        }
    }

    private static func matches(_ title: String, filename: String) -> Bool {
        let normalizedTitle = normalize(title)
        return !normalizedTitle.isEmpty && normalize(filename).contains(normalizedTitle)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func matchesSearch(_ query: String, item: IMDbWatchlistItem) -> Bool {
        let haystack = normalize([item.title, item.id, item.year.map(String.init) ?? ""].joined(separator: " "))
        return normalize(query).split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Library

final class LibraryPageViewController: PageViewController {
    private enum ViewMode: Int {
        case list, posters
    }

    private var viewMode = ViewMode.posters
    private var posterGridController: PosterGridViewController?
    private var detailController: DiscoverDetailViewController?
    private var searchQuery = ""

    private lazy var clearSearchButton: NSButton = {
        let button = NSButton(image: Theme.symbol("xmark.circle.fill", pointSize: 15, weight: .medium) ?? NSImage(), target: self, action: #selector(clearSearch))
        button.isBordered = false
        button.toolTip = "Clear search"
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }()

    private lazy var viewModeControl: NSSegmentedControl = {
        let control = modernFilterSegments(labels: ["List", "Posters"], action: #selector(viewModeChanged(_:)))
        control.selectedSegment = viewMode.rawValue
        return control
    }()

    enum Sort: String, CaseIterable {
        case added, title, size
        var label: String {
            switch self {
            case .added: "Recently Added"
            case .title: "Title"
            case .size: "Size"
            }
        }
        static let defaultsKey = "cargo.library.sort"
    }

    private var sort: Sort = Sort(rawValue: UserDefaults.standard.string(forKey: Sort.defaultsKey) ?? "") ?? .added {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Sort.defaultsKey)
            reload()
        }
    }

    /// The tabs above the list.
    enum Tab: Int, CaseIterable {
        case all, movies, shows, incomplete, unmatched
        var label: String {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .shows: "TV Shows"
            case .incomplete: "Incomplete"
            case .unmatched: "Unmatched"
            }
        }
        static let defaultsKey = "cargo.library.tab"
    }

    private var tab: Tab = Tab(rawValue: UserDefaults.standard.integer(forKey: Tab.defaultsKey)) ?? .all {
        didSet {
            UserDefaults.standard.set(tab.rawValue, forKey: Tab.defaultsKey)
            reload()
        }
    }

    override func leadingAccessoryView() -> NSView? {
        let control = modernFilterSegments(labels: Tab.allCases.map(\.label), action: #selector(tabChanged(_:)))
        control.selectedSegment = tab.rawValue
        let stack = NSStackView(views: [clearSearchButton, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        clearSearchButton.isHidden = searchQuery.isEmpty
        return stack
    }

    @objc private func clearSearch() {
        searchQuery = ""
        reload()
    }

    func focusSearchResult(id: String) {
        guard let item = coordinator.dashboardState.libraryItems.first(where: { $0.id == id }) else { return }
        if tab != .all { tab = .all }
        searchQuery = item.title
        reload()
    }

    func openSearchResult(id: String) {
        guard let item = coordinator.dashboardState.libraryItems.first(where: { $0.id == id }) else { return }
        if detailController != nil { hideDetail() }
        showDetail(for: item, metadata: coordinator.dashboardState.metadata[item.id])
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        tab = Tab(rawValue: sender.selectedSegment) ?? .all
    }

    override var subtitle: String {
        let items = coordinator.dashboardState.libraryItems
        guard !items.isEmpty else { return "" }
        let movies = items.filter { $0.kind == .movie }.count
        let shows = items.filter { $0.kind == .show }
        let episodes = shows.reduce(0) { $0 + $1.episodeCount }
        let size = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return "\(movies) movies · \(shows.count) shows · \(episodes) episodes · \(Formatters.bytes(size))"
    }

    override var emptyState: EmptyState {
        if coordinator.isRemoteClientMode {
            return EmptyState(
                symbol: "film.stack",
                title: "No resident library items yet",
                detail: "The resident’s organized library appears here."
            )
        }
        return EmptyState(
            symbol: "film.stack",
            title: coordinator.state.settings.hasLibraryRoot ? "Nothing in the library yet" : "No library folder",
            detail: coordinator.state.settings.hasLibraryRoot
                ? "Organized media shows up here as Movies and TV Shows."
                : "Choose the folder Infuse reads in Settings → Library."
        )
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Rescan Library", isEnabled: !coordinator.isRemoteClientMode) { [weak self] in self?.coordinator.scanLibrary() },
            RowAction(title: "Open Library in Finder", isEnabled: !coordinator.isRemoteClientMode && coordinator.libraryRootURL() != nil) { [weak self] in
                guard let url = self?.coordinator.libraryRootURL() else { return }
                NSWorkspace.shared.open(url)
            }
        ]
    }

    override func accessoryView() -> NSView? {
        let popup = modernFilterPopup(symbolName: "arrow.up.arrow.down")
        for option in Sort.allCases {
            popup.addItem(withTitle: "Sort by \(option.label)")
            popup.lastItem?.representedObject = option.rawValue
        }
        popup.selectItem(at: Sort.allCases.firstIndex(of: sort) ?? 0)
        popup.target = self
        popup.action = #selector(sortChanged(_:))
        let stack = NSStackView(views: [viewModeControl, popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    override func refreshAccessories() {
        viewModeControl.selectedSegment = viewMode.rawValue
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let grid = PosterGridViewController()
        posterGridController = grid
        addChild(grid)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid.view)
        NSLayoutConstraint.activate([
            grid.view.leadingAnchor.constraint(equalTo: list.view.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: list.view.trailingAnchor),
            grid.view.topAnchor.constraint(equalTo: list.view.topAnchor),
            grid.view.bottomAnchor.constraint(equalTo: list.view.bottomAnchor)
        ])
        reload()
    }

    override func reload() {
        guard let posterGridController else {
            super.reload()
            return
        }

        let showingGrid = viewMode == .posters
        list.emptyState = emptyState
        posterGridController.emptyState = emptyState
        if showingGrid {
            posterGridController.apply(posterRows())
        } else {
            list.apply(sections())
        }
        refreshAccessories()
        updateLibraryPresentation()
    }

    private func posterRows() -> [ListRow] {
        sections().flatMap(\.rows)
    }

    private func updateLibraryPresentation() {
        guard let posterGridController else { return }
        if detailController != nil {
            setHidden(true, for: list.view)
            setHidden(true, for: posterGridController.view)
            return
        }
        let showingGrid = viewMode == .posters
        setHidden(showingGrid, for: list.view)
        setHidden(!showingGrid, for: posterGridController.view)
    }

    private func setHidden(_ hidden: Bool, for view: NSView) {
        guard view.isHidden != hidden else { return }
        view.isHidden = hidden
    }

    private func showDetail(for item: LibraryItem, metadata: TMDBMetadata?) {
        guard detailController == nil else { return }
        let title = DiscoverTitle(
            id: item.id,
            title: item.title,
            year: item.year,
            kind: item.kind == .movie ? .movie : .series,
            posterURL: metadata?.posterURL,
            overview: nil,
            rating: nil,
            genres: [],
            networks: [],
            imdbID: nil,
            externalURL: nil,
            searchQuery: item.year.map { "\(item.title) \($0)" } ?? item.title
        )
        let detail = DiscoverDetailViewController(
            seed: title,
            coordinator: coordinator,
            onBack: { [weak self] in self?.hideDetail() },
            backButtonTitle: "Back to Library"
        )
        detailController = detail
        addChild(detail)
        detail.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(detail.view)
        NSLayoutConstraint.activate([
            detail.view.leadingAnchor.constraint(equalTo: list.view.leadingAnchor),
            detail.view.trailingAnchor.constraint(equalTo: list.view.trailingAnchor),
            detail.view.topAnchor.constraint(equalTo: list.view.topAnchor),
            detail.view.bottomAnchor.constraint(equalTo: list.view.bottomAnchor)
        ])
        updateLibraryPresentation()
    }

    private func hideDetail() {
        guard let detail = detailController else { return }
        detail.view.removeFromSuperview()
        detail.removeFromParent()
        detailController = nil
        updateLibraryPresentation()
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let next = Sort(rawValue: raw) else { return }
        sort = next
    }

    @objc private func viewModeChanged(_ sender: NSSegmentedControl) {
        viewMode = ViewMode(rawValue: sender.selectedSegment) ?? .list
        reload()
    }

    private func sorted(_ items: [LibraryItem]) -> [LibraryItem] {
        switch sort {
        case .added: items.sorted { $0.addedAt > $1.addedAt }
        case .title: items.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .size: items.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    override func sections() -> [ListSection] {
        let state = coordinator.dashboardState
        if coordinator.isRemoteClientMode {
            return remoteSections(state: state)
        }
        guard let root = coordinator.libraryRootURL() else { return [] }
        func row(_ item: LibraryItem) -> ListRow {
            let meta = state.metadata[item.id]
            let url = root.appendingPathComponent(item.relativePath)
            let missing = coordinator.missingEpisodes(for: item)
            var details: [String] = []
            var badge: StatusBadge?
            var primary: RowAction?
            if meta == nil, coordinator.hasTMDBKey {
                let missed = state.metadataMisses[item.id] != nil
                badge = .neutral(missed ? "No TMDB match" : "Not looked up yet")
            }
            switch item.kind {
            case .movie:
                let subs = SubtitleService.hasSubtitle(url) ? " · subtitles" : ""
                details.append("\(Formatters.bytes(item.sizeBytes)) · added \(Formatters.date.string(from: item.addedAt))\(subs)")
            case .show:
                details.append("\(item.seasonCount) season\(item.seasonCount == 1 ? "" : "s") · \(item.episodeCount) episode\(item.episodeCount == 1 ? "" : "s") · \(Formatters.bytes(item.sizeBytes)) · added \(Formatters.date.string(from: item.addedAt))")
                if let counts = meta?.episodeCounts, !counts.isEmpty {
                    // Completeness per season, the thing Infuse never tells you.
                    if missing.isEmpty {
                        badge = .success("Complete")
                    } else {
                        badge = .warning("Incomplete")
                        details.append(missing.keys.sorted().map { season in
                            "Season \(season) · \(item.episodes[season]?.count ?? 0) of \(counts[season] ?? 0)"
                        }.joined(separator: "  ·  "))
                        primary = RowAction(title: "Find on Put.io") { [weak self] in
                            self?.findMissing(for: item)
                        }
                    }
                }
            }
            let reveal = RowAction(title: "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            let play = RowAction(title: "Play in Infuse", isEnabled: item.kind == .movie) {
                var components = URLComponents(string: "infuse://x-callback-url/play")
                components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
                if let infuse = components?.url { NSWorkspace.shared.open(infuse) }
            }
            let openDetail = RowAction(title: "View Details") { [weak self] in
                self?.showDetail(for: item, metadata: meta)
            }
            var menu = [reveal, play]
            menu.insert(openDetail, at: 0)
            if let primary { menu.insert(primary, at: 0) }
            if let meta {
                menu.append(RowAction(title: "Open on TMDB") { NSWorkspace.shared.open(meta.pageURL) })
            }
            menu.append(RowAction(title: "Get Subtitles") { [weak self] in
                guard let self else { return }
                run {
                    let result = await self.coordinator.fetchSubtitles(for: item)
                    let alert = NSAlert()
                    alert.messageText = result.saved == 0 && result.failed == 0
                        ? "\(item.displayTitle) already has subtitles"
                        : "Saved \(result.saved) subtitle\(result.saved == 1 ? "" : "s")" + (result.failed > 0 ? " · \(result.failed) not found" : "")
                    alert.runModal()
                }
            })
            menu.append(RowAction(title: "Search on IMDb") {
                var components = URLComponents(string: "https://www.imdb.com/find/")
                components?.queryItems = [URLQueryItem(name: "q", value: item.displayTitle), URLQueryItem(name: "s", value: "tt")]
                if let url = components?.url { NSWorkspace.shared.open(url) }
            })
            menu.append(copyAction("Copy Path", url.path))
            menu.append(RowAction(
                title: "Move to Trash…",
                isDestructive: true,
                isSeparatorBefore: true,
                confirmation: .init(message: "Move “\(item.displayTitle)” to the Trash?", detail: "The files leave the library; Infuse will stop showing it. Recoverable from the Trash.", button: "Move to Trash", pluralMessage: "Move %d titles to the Trash?")
            ) { [weak self] in
                guard let self else { return }
                do { try coordinator.deleteLibraryItem(item) } catch { NSAlert(error: error).runModal() }
            })
            return ListRow(
                id: item.id,
                title: item.displayTitle,
                details: details,
                badge: badge,
                thumbnail: meta?.posterURL,
                primaryAction: openDetail,
                menuActions: menu
            )
        }
        let visible = state.libraryItems.filter { item in
            let matchesSearch = searchQuery.isEmpty || Self.matchesSearch(searchQuery, item: item)
            guard matchesSearch else { return false }
            switch tab {
            case .all: return true
            case .movies: return item.kind == .movie
            case .shows: return item.kind == .show
            case .incomplete: return !coordinator.missingEpisodes(for: item).isEmpty
            case .unmatched: return state.metadata[item.id] == nil
            }
        }
        let movies = sorted(visible.filter { $0.kind == .movie }).map(row)
        let shows = sorted(visible.filter { $0.kind == .show }).map(row)
        if tab == .movies { return [ListSection(rows: movies)] }
        if tab == .shows || tab == .incomplete { return [ListSection(rows: shows)] }
        if tab == .unmatched, movies.isEmpty || shows.isEmpty { return [ListSection(rows: movies + shows)] }
        return [ListSection(title: "Movies", rows: movies), ListSection(title: "TV Shows", rows: shows)]
    }

    private func remoteSections(state: CargoState) -> [ListSection] {
        let visible = state.libraryItems.filter { item in
            let matchesSearch = searchQuery.isEmpty || Self.matchesSearch(searchQuery, item: item)
            guard matchesSearch else { return false }
            switch tab {
            case .all: return true
            case .movies: return item.kind == .movie
            case .shows, .incomplete: return item.kind == .show
            case .unmatched: return false
            }
        }
        let rows = sorted(visible).map { item in
            let detail = item.kind == .movie
                ? "Movie · \(Formatters.bytes(item.sizeBytes)) · \(item.relativePath)"
                : "TV show · \(item.seasonCount) season\(item.seasonCount == 1 ? "" : "s") · \(item.episodeCount) episode\(item.episodeCount == 1 ? "" : "s") · \(item.relativePath)"
            return ListRow(
                id: item.id,
                title: item.displayTitle,
                details: [detail],
                badge: item.kind == .show ? .neutral("Resident library") : nil,
                primaryAction: copyAction("Copy Relative Path", item.relativePath),
                menuActions: [copyAction("Copy Relative Path", item.relativePath)]
            )
        }
        return [ListSection(rows: rows)]
    }

    private static func matchesSearch(_ query: String, item: LibraryItem) -> Bool {
        let normalizedQuery = normalizeSearch(query)
        guard !normalizedQuery.isEmpty else { return true }
        let haystack = normalizeSearch([item.title, item.displayTitle, item.relativePath, item.year.map(String.init) ?? ""].joined(separator: " "))
        return normalizedQuery.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    private static func normalizeSearch(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func findMissing(for item: LibraryItem) {
        run { [weak self] in
            guard let self else { return }
            let result = try await coordinator.findMissingOnPutIO(for: item)
            let alert = NSAlert()
            if result.queued.isEmpty {
                alert.messageText = "Nothing on Put.io for \(item.title)"
                alert.informativeText = "None of the \(result.stillMissing) missing episodes are in your Put.io account. ShowRSS or a manual transfer has to bring them in first."
            } else {
                alert.messageText = "Queued \(result.queued.count) episode\(result.queued.count == 1 ? "" : "s") from Put.io"
                alert.informativeText = result.queued.joined(separator: "\n") + (result.stillMissing > 0 ? "\n\n\(result.stillMissing) still missing." : "")
            }
            alert.runModal()
        }
    }
}

// MARK: - History

final class HistoryPageViewController: PageViewController {
    override var emptyState: EmptyState {
        EmptyState(symbol: "clock", title: "No workflow activity yet")
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Clear History", isDestructive: true, isEnabled: !coordinator.dashboardState.history.isEmpty) { [weak self] in
                guard let self, confirm("Clear the history?", detail: "Routine entries expire after 30 days on their own; warnings and failures after 90.", button: "Clear") else { return }
                coordinator.clearHistory()
            },
            refreshAction()
        ]
    }

    private lazy var clearHistoryButton = barButton("Clear History", action: #selector(clearHistory))

    override func accessoryView() -> NSView? { clearHistoryButton }

    override func refreshAccessories() {
        clearHistoryButton.isEnabled = !coordinator.dashboardState.history.isEmpty
    }

    @objc private func clearHistory() {
        guard confirm("Clear the history?", detail: "Routine entries expire after 30 days on their own; warnings and failures after 90.", button: "Clear") else { return }
        coordinator.clearHistory()
    }

    override func sections() -> [ListSection] {
        let rows = coordinator.dashboardState.history.prefix(200).map { entry in
            ListRow(
                id: entry.id.uuidString,
                title: entry.title,
                titleColor: Self.color(for: entry.kind),
                details: ["\(Formatters.dateTime.string(from: entry.date)) · \(entry.detail)"],
                badge: Self.badge(for: entry.kind),
                menuActions: [copyAction("Copy Entry", "\(entry.title) — \(entry.detail)")]
            )
        }
        return [ListSection(rows: rows)]
    }

    private static func color(for kind: CargoHistoryKind) -> NSColor? {
        switch kind {
        case .info, .success: nil
        case .warning: .systemOrange
        case .failure: .systemRed
        }
    }

    private static func badge(for kind: CargoHistoryKind) -> StatusBadge? {
        switch kind {
        case .info: nil
        case .success: .success("OK")
        case .warning: .warning("Warning")
        case .failure: .failure("Failed")
        }
    }
}
