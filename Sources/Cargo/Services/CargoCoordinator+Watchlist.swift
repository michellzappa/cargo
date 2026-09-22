import Foundation

// IMDb watchlist as a desired list.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    private func clientWatchlistKey(_ clientID: UUID) -> String {
        clientID.uuidString.lowercased()
    }

    func clientWatchlist(for clientID: UUID) -> CargoClientWatchlist? {
        state.clientWatchlists[clientWatchlistKey(clientID)]
    }

    func saveIMDbWatchlistURL(_ value: String) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              url.scheme == "https",
              url.host?.lowercased().hasSuffix("imdb.com") == true,
              url.path.lowercased().contains("watchlist") else {
            throw SettingsError.invalidIMDbWatchlistURL
        }

        if state.settings.imdbWatchlistURL != url.absoluteString {
            state.settings.imdbWatchlistURL = url.absoluteString
            state.imdbWatchlistItems = []
            state.imdbWatchlistLastUpdated = nil
        }
        state.lastUpdated = Date()
        imdbWatchlistStatus = "Ready to sync"
        try store.replace(with: state)
    }

    func refreshIMDbWatchlist(force: Bool = true) async -> [String] {
        if isRemoteClientMode {
            _ = try? await remoteClientSession.execute(
                .refreshPersonalWatchlist(url: state.settings.imdbWatchlistURL)
            )
            return []
        }
        guard !state.settings.imdbWatchlistURL.isEmpty else {
            imdbWatchlistStatus = "No Watchlist URL"
            return []
        }

        if !force,
           let lastUpdated = state.imdbWatchlistLastUpdated,
           Date().timeIntervalSince(lastUpdated) < 15 * 60 {
            return []
        }

        do {
            let previousIDs = Set(state.imdbWatchlistItems.map(\.id))
            let items = try await imdbWatchlistService.fetchItems(from: state.settings.imdbWatchlistURL)
            state.imdbWatchlistItems = items.sorted {
                if let lhsDate = $0.addedAt, let rhsDate = $1.addedAt, lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                if ($0.addedAt != nil) != ($1.addedAt != nil) {
                    return $0.addedAt != nil
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            state.imdbWatchlistLastUpdated = Date()
            try persist()
            imdbWatchlistStatus = "Updated \(Self.watchlistTimeFormatter.string(from: Date())) · \(items.count) titles"

            let addedItems = items.filter { !previousIDs.contains($0.id) }
            if !addedItems.isEmpty {
                let detail = addedItems.map { item in
                    item.year.map { "\(item.title) (\($0))" } ?? item.title
                }.joined(separator: ", ")
                recordHistory(
                    kind: .info,
                    title: "IMDb Watchlist updated",
                    detail: "Added \(addedItems.count) title\(addedItems.count == 1 ? "" : "s"): \(detail)"
                )
            }
            return addedItems.map(\.title)
        } catch {
            imdbWatchlistStatus = error.localizedDescription
            return []
        }
    }

    /// Refreshes a connected client's personal list without changing the
    /// resident IMDb list or entering the resident download automation.
    @discardableResult
    func refreshClientWatchlist(for clientID: UUID, requestedURL: String? = nil) async -> [String] {
        let key = clientWatchlistKey(clientID)
        var watchlist = state.clientWatchlists[key] ?? CargoClientWatchlist()

        if let requestedURL {
            let trimmedValue = requestedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValue.isEmpty {
                watchlist = CargoClientWatchlist(status: "No Watchlist URL")
                state.clientWatchlists[key] = watchlist
                persistQuietly()
                return []
            }
            guard let url = URL(string: trimmedValue),
                  url.scheme == "https",
                  url.host?.lowercased().hasSuffix("imdb.com") == true,
                  url.path.lowercased().contains("watchlist") else {
                watchlist.status = SettingsError.invalidIMDbWatchlistURL.localizedDescription
                state.clientWatchlists[key] = watchlist
                persistQuietly()
                return []
            }
            let normalizedURL = url.absoluteString
            if watchlist.url != normalizedURL {
                watchlist.url = normalizedURL
                watchlist.items = []
                watchlist.lastUpdated = nil
            }
        }

        guard !watchlist.url.isEmpty else {
            watchlist.status = "No Watchlist URL"
            state.clientWatchlists[key] = watchlist
            persistQuietly()
            return []
        }

        do {
            let previousIDs = Set(watchlist.items.map(\.id))
            let items = try await imdbWatchlistService.fetchItems(from: watchlist.url)
            watchlist.items = items.sorted {
                if let lhsDate = $0.addedAt, let rhsDate = $1.addedAt, lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                if ($0.addedAt != nil) != ($1.addedAt != nil) {
                    return $0.addedAt != nil
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            watchlist.lastUpdated = Date()
            watchlist.status = "Updated \(Self.watchlistTimeFormatter.string(from: Date())) · \(items.count) titles"
            state.clientWatchlists[key] = watchlist
            persistQuietly()

            let addedItems = items.filter { !previousIDs.contains($0.id) }
            return addedItems.map(\.title)
        } catch {
            watchlist.status = error.localizedDescription
            state.clientWatchlists[key] = watchlist
            persistQuietly()
            return []
        }
    }
}
