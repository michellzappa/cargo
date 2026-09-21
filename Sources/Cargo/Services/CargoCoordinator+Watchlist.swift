import Foundation

// IMDb watchlist as a desired list.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
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
            _ = try? await remoteClientSession.execute(.refreshWatchlist)
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
}
