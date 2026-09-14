import AppKit

/// Sidebar destinations. Settings lives in its own window (⌘,).
enum Page: Int, CaseIterable {
    case transfers
    case files
    case inbox
    case watchlist
    case history

    var title: String {
        switch self {
        case .transfers: "Transfers"
        case .files: "Files"
        case .inbox: "Inbox"
        case .watchlist: "Watchlist"
        case .history: "History"
        }
    }

    var symbolName: String {
        switch self {
        case .transfers: "arrow.down.circle"
        case .files: "folder"
        case .inbox: "tray"
        case .watchlist: "star"
        case .history: "clock"
        }
    }

    @MainActor
    func count(in coordinator: CargoCoordinator) -> Int {
        switch self {
        case .transfers: coordinator.state.transfers.count
        case .files: coordinator.state.remoteMediaFiles.count
        case .inbox: coordinator.inboxFileURLs().count
        case .watchlist: coordinator.state.imdbWatchlistItems.count
        case .history: coordinator.state.history.count
        }
    }

    @MainActor
    func makeViewController(coordinator: CargoCoordinator) -> PageViewController {
        switch self {
        case .transfers: TransfersPageViewController(page: self, coordinator: coordinator)
        case .files: FilesPageViewController(page: self, coordinator: coordinator)
        case .inbox: InboxPageViewController(page: self, coordinator: coordinator)
        case .watchlist: WatchlistPageViewController(page: self, coordinator: coordinator)
        case .history: HistoryPageViewController(page: self, coordinator: coordinator)
        }
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
        if let accessory = accessoryView() {
            // Thin control strip above the list (sort menus and the like).
            let bar = NSStackView(views: [NSView(), accessory])
            bar.orientation = .horizontal
            bar.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 4, right: 20)
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bar.topAnchor.constraint(equalTo: view.topAnchor)
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
    }

    // Subclass API
    var emptyState: EmptyState { EmptyState(symbol: page.symbolName, title: "Nothing here") }
    func sections() -> [ListSection] { [] }
    func listActions() -> [RowAction] { [refreshAction()] }
    /// Optional control shown right-aligned above the list.
    func accessoryView() -> NSView? { nil }

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

    override func sections() -> [ListSection] {
        let rows = coordinator.state.transfers.map { transfer -> ListRow in
            let isActive = transfer.status == .downloading || transfer.status == .waiting
            var actions: [RowAction] = []
            if transfer.status == .failed {
                actions.append(RowAction(title: "Retry") { [weak self] in
                    self?.run { try await self?.coordinator.retryTransfer(id: transfer.id) }
                })
            }
            actions.append(RowAction(title: isActive ? "Cancel Transfer" : "Remove Transfer", isDestructive: true) { [weak self] in
                guard let self else { return }
                guard confirm(
                    "\(isActive ? "Cancel" : "Remove") “\(transfer.name)”?",
                    detail: isActive ? "The download stops and is removed from Put.io." : "Files already in Put.io are kept.",
                    button: isActive ? "Cancel Transfer" : "Remove"
                ) else { return }
                run { try await self.coordinator.cancelTransfer(id: transfer.id) }
            })
            actions.append(copyAction("Copy Name", transfer.name))

            return ListRow(
                id: String(transfer.id),
                title: transfer.name,
                details: ["\(Formatters.percent(transfer.progress)) · \(Formatters.bytes(transfer.sizeBytes))"],
                badge: Self.badge(for: transfer.status),
                progress: isActive ? transfer.progress : nil,
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

// MARK: - Files

final class FilesPageViewController: PageViewController {
    override var emptyState: EmptyState {
        EmptyState(symbol: "folder", title: "No video files in Put.io", detail: coordinator.isConnected ? nil : coordinator.putIOStatus)
    }

    override func sections() -> [ListSection] {
        let state = coordinator.state
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

            let sync = RowAction(title: job == nil ? "Sync" : "Downloaded", isEnabled: job == nil && !deleted) { [weak self] in
                guard let self else { return }
                coordinator.enqueueLocalSync(remoteFileID: file.id)
                Task { await self.coordinator.processLocalSync(remoteFileID: file.id) }
            }
            let delete = RowAction(title: "Delete from Put.io…", isDestructive: true, isEnabled: !deleted, isSeparatorBefore: true) { [weak self] in
                guard let self else { return }
                guard confirm(
                    "Delete “\(file.displayPath)” from Put.io?",
                    detail: "It goes to Put.io's trash; empty the trash in Settings → Put.io to free the space. Local copies are not affected.",
                    button: "Delete"
                ) else { return }
                run { try await self.coordinator.deleteRemoteFile(remoteFileID: file.id) }
            }
            let subtitles = RowAction(title: "Download Subtitles…", isEnabled: !deleted) { [weak self] in
                self?.chooseSubtitle(for: file)
            }
            let copyLink = RowAction(title: "Copy Download Link", isEnabled: !deleted) { [weak self] in
                self?.run {
                    guard let url = try await self?.coordinator.downloadURL(remoteFileID: file.id) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }

            return ListRow(
                id: String(file.id),
                title: file.displayPath,
                details: ["\(file.type.displayName) · \(Formatters.bytes(file.sizeBytes))"],
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
            let delete = RowAction(title: "Delete from Put.io…", isDestructive: true, isSeparatorBefore: true) { [weak self] in
                guard let self, confirm(
                    "Delete “\(archive.displayPath)” from Put.io?",
                    detail: "It goes to Put.io's trash; empty the trash in Settings → Put.io to free the space.",
                    button: "Delete"
                ) else { return }
                run { try await self.coordinator.deleteRemoteFile(remoteFileID: archive.id) }
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
            detail: "Synced files land in \(coordinator.state.settings.stagingDirectoryName) and show up here."
        )
    }

    override func listActions() -> [RowAction] {
        let inbox = coordinator.libraryRootURL()?
            .appendingPathComponent(coordinator.state.settings.stagingDirectoryName, isDirectory: true)
        return [
            RowAction(title: "Open Inbox in Finder", isEnabled: inbox != nil) {
                guard let inbox else { return }
                NSWorkspace.shared.open(inbox)
            },
            RowAction(title: "Clear Failed", isEnabled: coordinator.state.localJobs.contains { $0.status == .failed }) { [weak self] in
                self?.coordinator.clearFailedJobs()
            },
            refreshAction()
        ]
    }

    override func sections() -> [ListSection] {
        let state = coordinator.state

        let downloading = state.localJobs
            .filter { [.queued, .downloading, .importing, .failed].contains($0.status) }
            .map { job in
                ListRow(
                    id: job.id.uuidString,
                    title: job.name,
                    details: [job.destination ?? "Destination not chosen", job.errorMessage].compactMap { $0 },
                    badge: Self.badge(for: job.status),
                    progress: job.status == .downloading ? job.progress : nil,
                    menuActions: [copyAction("Copy Name", job.name), revealAction(job.destination)]
                )
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
                    title: entry.name,
                    details: [
                        destination.map { "→ \($0)" } ?? "Review manually · \(preview.explanation)",
                        entry.job == nil ? "Not tracked by Cargo" : nil
                    ].compactMap { $0 },
                    badge: badge,
                    primaryAction: organize,
                    menuActions: [
                        organize,
                        revealAction(entry.sourceURL.path),
                        copyAction("Copy Path", entry.sourceURL.path),
                        RowAction(title: "Move to Trash", isDestructive: true, isEnabled: exists, isSeparatorBefore: true) { [weak self] in
                            guard let self, confirm("Move “\(entry.name)” to Trash?", detail: "The file is removed from the Inbox.", button: "Move to Trash") else { return }
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
                ListRow(
                    id: "organized-\(job.id.uuidString)",
                    title: job.name,
                    details: [job.destination ?? "Destination unavailable"],
                    badge: .success("Organized"),
                    menuActions: [revealAction(job.destination), copyAction("Copy Name", job.name)]
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

    enum Filter: String, CaseIterable {
        case all, wanted, notOrganized
        var label: String {
            switch self {
            case .all: "Everything"
            case .wanted: "Wanted only"
            case .notOrganized: "Not organized"
            }
        }
        static let defaultsKey = "cargo.watchlist.filter"
    }

    private var filter: Filter = Filter(rawValue: UserDefaults.standard.string(forKey: Filter.defaultsKey) ?? "") ?? .all {
        didSet {
            UserDefaults.standard.set(filter.rawValue, forKey: Filter.defaultsKey)
            reload()
        }
    }

    override func accessoryView() -> NSView? {
        let filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        filterPopup.controlSize = .small
        filterPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for option in Filter.allCases {
            filterPopup.addItem(withTitle: "Show \(option.label)")
            filterPopup.lastItem?.representedObject = option.rawValue
        }
        filterPopup.selectItem(at: Filter.allCases.firstIndex(of: filter) ?? 0)
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged(_:))
        let stack = NSStackView(views: [filterPopup, sortPopup()])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    @objc private func filterChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let next = Filter(rawValue: raw) else { return }
        filter = next
    }

    private func sortPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
        let state = coordinator.state
        guard !state.imdbWatchlistItems.isEmpty else { return coordinator.imdbWatchlistStatus }
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
        EmptyState(symbol: "star", title: "No Watchlist titles yet", detail: coordinator.imdbWatchlistStatus)
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
        let state = coordinator.state
        let visible = state.imdbWatchlistItems.filter { item in
            switch filter {
            case .all: true
            case .wanted: Self.status(for: item, state: state).text == "Wanted"
            case .notOrganized: Self.status(for: item, state: state).text != "Organized"
            }
        }
        let rows = sorted(visible, state: state).map { item -> ListRow in
            let search = RowAction(title: "Search") {
                var components = URLComponents(string: "https://chill.institute/search")
                components?.queryItems = [URLQueryItem(name: "q", value: item.title)]
                if let url = components?.url { NSWorkspace.shared.open(url) }
            }
            let imdb = RowAction(title: "Open on IMDb", isEnabled: item.id.hasPrefix("tt")) {
                if let url = URL(string: "https://www.imdb.com/title/\(item.id)/") { NSWorkspace.shared.open(url) }
            }
            let added = item.addedAt.map { "Added \(Formatters.date.string(from: $0))" } ?? item.id
            return ListRow(
                id: item.id,
                title: item.year.map { "\(item.title) (\($0))" } ?? item.title,
                details: [[item.titleType, added].compactMap { $0 }.joined(separator: " · ")],
                badge: Self.status(for: item, state: state),
                primaryAction: search,
                menuActions: [search, imdb, copyAction("Copy Title", item.title)]
            )
        }
        return [ListSection(rows: rows)]
    }

    static func status(for item: IMDbWatchlistItem, state: CargoState) -> StatusBadge {
        let matching = state.localJobs.filter { matches(item.title, filename: $0.name) }
        if matching.contains(where: { $0.status == .completed }) { return .success("Organized") }
        if matching.contains(where: { $0.status == .needsReview }) { return .highlight("In Inbox") }
        if matching.contains(where: { [.queued, .downloading, .importing].contains($0.status) }) { return .info("Queued") }
        if state.remoteMediaFiles.contains(where: { matches(item.title, filename: $0.displayPath) }) { return .info("Available") }
        return .warning("Wanted")
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
}

// MARK: - History

final class HistoryPageViewController: PageViewController {
    override var emptyState: EmptyState {
        EmptyState(symbol: "clock", title: "No workflow activity yet")
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Clear History", isDestructive: true, isEnabled: !coordinator.state.history.isEmpty) { [weak self] in
                guard let self, confirm("Clear the history?", detail: "Routine entries expire after 30 days on their own; warnings and failures after 90.", button: "Clear") else { return }
                coordinator.clearHistory()
            },
            refreshAction()
        ]
    }

    override func accessoryView() -> NSView? {
        let button = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    @objc private func clearHistory() {
        guard confirm("Clear the history?", detail: "Routine entries expire after 30 days on their own; warnings and failures after 90.", button: "Clear") else { return }
        coordinator.clearHistory()
    }

    override func sections() -> [ListSection] {
        let rows = coordinator.state.history.prefix(200).map { entry in
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
