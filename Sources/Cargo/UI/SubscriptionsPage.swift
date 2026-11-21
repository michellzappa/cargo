import AppKit

/// Series and feeds Cargo follows. Subscribing stores the subscription and its
/// episode ledger; fetching new episodes is the background cycle's job.
final class SubscriptionsPageViewController: PageViewController {
    private enum Filter: Int {
        case all, series, feeds
    }

    private var filter = Filter.all

    private lazy var filterControl: NSSegmentedControl = {
        let control = modernFilterSegments(labels: ["All", "Series", "Feeds"], action: #selector(filterChanged(_:)))
        control.selectedSegment = filter.rawValue
        return control
    }()

    private lazy var addSeriesButton = barButton("Add Series…", action: #selector(addSeries))
    private lazy var addFeedButton = barButton("Add Feed…", action: #selector(addFeed))

    override var emptyState: EmptyState {
        EmptyState(
            symbol: page.symbolName,
            title: "No subscriptions yet",
            detail: "Add a series by name, or use Subscribe on a show in Library or Discover."
        )
    }

    override func leadingAccessoryView() -> NSView? { filterControl }

    override func accessoryView() -> NSView? {
        let stack = NSStackView(views: [addSeriesButton, addFeedButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    override func listActions() -> [RowAction] {
        [
            RowAction(title: "Add Series…") { [weak self] in self?.addSeries() },
            RowAction(title: "Add Feed…") { [weak self] in self?.addFeed() }
        ]
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filter = Filter(rawValue: sender.selectedSegment) ?? .all
        reload()
    }

    override func sections() -> [ListSection] {
        let subscriptions = coordinator.dashboardState.subscriptions
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let series = subscriptions.filter { $0.imdbID != nil }
        let feeds = subscriptions.filter { $0.feedURL != nil }
        var result: [ListSection] = []
        if filter != .feeds, !series.isEmpty {
            result.append(ListSection(title: "Series", rows: series.map(row)))
        }
        if filter != .series, !feeds.isEmpty {
            result.append(ListSection(title: "Feeds", rows: feeds.map(row)))
        }
        return result
    }

    private func row(for subscription: Subscription) -> ListRow {
        var details: [String] = []
        var title = subscription.title
        switch subscription.kind {
        case .series(_, _, _, let year):
            if let year { title += " (\(year))" }
            details.append("Series · \(subscription.backfill.displayName) · added \(Formatters.date.string(from: subscription.createdAt))")
        case .feed(_, _, let keywords, let unwanted):
            let backfill = subscription.backfill == .newOnly ? "New items only" : subscription.backfill.displayName
            var line = "Feed · \(backfill)"
            if !keywords.isEmpty { line += " · must match \(keywords.joined(separator: ", "))" }
            if !unwanted.isEmpty { line += " · skips \(unwanted.joined(separator: ", "))" }
            details.append(line)
        }
        let ledger = ledgerSummary(for: subscription)
        let checked = subscription.lastCheckedAt.map { "Last checked \(Formatters.dateTime.string(from: $0))" } ?? "Not checked yet"
        details.append(ledger.isEmpty ? checked : "\(checked) · \(ledger)")
        if let error = subscription.lastError, !error.isEmpty {
            details.append(error)
        }

        let badge: StatusBadge = if subscription.paused {
            .neutral("Paused")
        } else if subscription.lastError?.isEmpty == false {
            .failure("Error")
        } else {
            .success("Active")
        }

        return ListRow(
            id: subscription.id.uuidString,
            title: title,
            details: details,
            badge: badge,
            thumbnail: coordinator.posterURL(for: subscription),
            menuActions: menuActions(for: subscription)
        )
    }

    /// "4 episodes · 1 sent" from the ledger entries that belong to this subscription.
    private func ledgerSummary(for subscription: Subscription) -> String {
        let entries = coordinator.dashboardState.episodeLedger.filter { entry in
            entry.subscriptionID == subscription.id
                || (subscription.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) == EpisodeLedgerEntry.normalizeIMDbID(entry.imdbID))
        }
        guard !entries.isEmpty else { return "" }
        var parts = ["\(entries.count) episode\(entries.count == 1 ? "" : "s")"]
        let counts = Dictionary(grouping: entries, by: \.state).mapValues(\.count)
        for state in EpisodeLedgerState.allCases {
            if let count = counts[state], count > 0 { parts.append("\(count) \(state.displayName.lowercased())") }
        }
        return parts.joined(separator: " · ")
    }

    private func menuActions(for subscription: Subscription) -> [RowAction] {
        var actions: [RowAction] = [
            RowAction(title: subscription.paused ? "Resume" : "Pause") { [weak self] in
                guard let self else { return }
                run { try await self.coordinator.setSubscriptionPausedFromDashboard(id: subscription.id, paused: !subscription.paused) }
            }
        ]
        if let tmdbID = subscription.tmdbID, let url = URL(string: "https://www.themoviedb.org/tv/\(tmdbID)") {
            actions.append(RowAction(title: "Open on TMDB") { NSWorkspace.shared.open(url) })
        }
        if let imdbID = subscription.imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") {
            actions.append(RowAction(title: "Open on IMDb") { NSWorkspace.shared.open(url) })
        }
        if let feedURL = subscription.feedURL {
            actions.append(copyAction("Copy Feed URL", feedURL))
        }
        actions.append(RowAction(
            title: "Unsubscribe",
            isDestructive: true,
            isSeparatorBefore: true,
            confirmation: RowAction.Confirmation(
                message: "Unsubscribe from \(subscription.title)?",
                detail: "Cargo stops following it. Files you already have stay where they are.",
                button: "Unsubscribe",
                pluralMessage: "Unsubscribe from %d subscriptions?"
            )
        ) { [weak self] in
            guard let self else { return }
            run { try await self.coordinator.unsubscribe(id: subscription.id) }
        })
        return actions
    }

    // MARK: - Adding

    @objc private func addSeries() {
        guard coordinator.hasTMDBKey || coordinator.isRemoteClientMode else {
            let alert = NSAlert()
            alert.messageText = "Add a TMDB key first"
            alert.informativeText = "Cargo finds series and their episodes on TMDB. Add a key in Settings → Library."
            alert.runModal()
            return
        }
        let field = NSTextField(string: "")
        field.placeholderString = "Series name, for example Severance"
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let alert = NSAlert()
        alert.messageText = "Add a series"
        alert.informativeText = "Cargo looks the name up on TMDB."
        alert.accessoryView = field
        alert.addButton(withTitle: "Find")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (name, year) = Self.nameAndYear(field.stringValue)
        guard !name.isEmpty else { return }
        run {
            let metadata = try await self.coordinator.fetchDiscoverMetadata(title: name, year: year, type: .tv, imdbID: nil)
            guard self.confirmSubscribe(to: metadata) else { return }
            try await self.coordinator.subscribeSeries(metadata: metadata)
        }
    }

    /// Shows what TMDB matched, so a wrong match is caught before it is saved.
    private func confirmSubscribe(to metadata: TMDBMetadata) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Subscribe to \(metadata.title)\(metadata.year.map { " (\($0))" } ?? "")?"
        var info = metadata.overview.map { String($0.prefix(280)) } ?? ""
        if coordinator.dashboardSeriesSubscription(imdbID: metadata.imdbID) != nil {
            info = "You already follow this series."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Subscribe")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func addFeed() {
        let urlField = NSTextField(string: "")
        urlField.placeholderString = "https://example.com/feed.rss"
        let titleField = NSTextField(string: "")
        titleField.placeholderString = "Name"
        let keywordsField = NSTextField(string: "")
        keywordsField.placeholderString = "Must contain (comma-separated, optional)"
        let unwantedField = NSTextField(string: "")
        unwantedField.placeholderString = "Skip if it contains (comma-separated, optional)"
        let stack = NSStackView(views: [urlField, titleField, keywordsField, unwantedField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 4 * 24 + 3 * 8)
        for field in [urlField, titleField, keywordsField, unwantedField] {
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }

        let alert = NSAlert()
        alert.messageText = "Add a feed"
        alert.informativeText = "Use an RSS or Atom feed that has magnet or torrent links."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = urlField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? (URL(string: url)?.host ?? url) : name
        run {
            try await self.coordinator.subscribeFeed(
                url: url,
                title: title,
                keywords: Self.list(keywordsField.stringValue),
                unwantedKeywords: Self.list(unwantedField.stringValue)
            )
        }
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// "Abbott Elementary 2021" → ("Abbott Elementary", 2021). A trailing year narrows the TMDB match.
    static func nameAndYear(_ text: String) -> (String, Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")
        if parts.count > 1, let last = parts.last,
           let year = Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "()"))), (1900...2100).contains(year) {
            return (parts.dropLast().joined(separator: " "), year)
        }
        return (trimmed, nil)
    }
}
