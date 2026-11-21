import Foundation

/// Validation and storage errors for subscriptions and the episode ledger.
enum SubscriptionError: LocalizedError, Equatable, Sendable {
    case invalidIMDbID
    case invalidTMDBID
    case emptyTitle
    case invalidFeedURL
    case duplicateSubscription
    case subscriptionNotFound
    case invalidEpisodeNumber
    case invalidQualityProfile

    var errorDescription: String? {
        switch self {
        case .invalidIMDbID:
            "Enter an IMDb ID such as tt11280740."
        case .invalidTMDBID:
            "Enter a positive TMDB ID."
        case .emptyTitle:
            "Subscription title cannot be empty."
        case .invalidFeedURL:
            "Enter an HTTP or HTTPS feed URL."
        case .duplicateSubscription:
            "Cargo already has a subscription for this source."
        case .subscriptionNotFound:
            "Cargo could not find that subscription."
        case .invalidEpisodeNumber:
            "Season and episode numbers must be positive."
        case .invalidQualityProfile:
            "Quality profile requires a resolution, a non-negative size cap, and a positive seeder pool."
        }
    }
}

// Subscriptions and episode ledger storage.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    @discardableResult
    func addSeriesSubscription(
        imdbID: String,
        tmdbID: Int,
        title: String,
        year: Int? = nil,
        quality: QualityProfile? = nil,
        backfill: SubscriptionBackfillPolicy = .newOnly,
        now: Date = Date()
    ) throws -> Subscription {
        let normalizedIMDbID = EpisodeLedgerEntry.normalizeIMDbID(imdbID)
        guard normalizedIMDbID.hasPrefix("tt"), normalizedIMDbID.count > 2 else {
            throw SubscriptionError.invalidIMDbID
        }
        guard tmdbID > 0 else {
            throw SubscriptionError.invalidTMDBID
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            throw SubscriptionError.emptyTitle
        }
        if let quality {
            try Self.validateQualityProfile(quality)
        }
        if state.subscriptions.contains(where: {
            $0.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) == normalizedIMDbID
        }) {
            throw SubscriptionError.duplicateSubscription
        }

        let subscription = Subscription(
            id: UUID(),
            kind: .series(imdbID: normalizedIMDbID, tmdbID: tmdbID, title: cleanedTitle, year: year),
            quality: quality,
            backfill: backfill,
            paused: false,
            createdAt: now
        )
        state.subscriptions.append(subscription)
        try persist()
        return subscription
    }

    @discardableResult
    func addFeedSubscription(
        url: String,
        title: String,
        keywords: [String] = [],
        unwantedKeywords: [String] = [],
        quality: QualityProfile? = nil,
        backfill: SubscriptionBackfillPolicy = .newOnly,
        now: Date = Date()
    ) throws -> Subscription {
        let cleanedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: cleanedURL),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false else {
            throw SubscriptionError.invalidFeedURL
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            throw SubscriptionError.emptyTitle
        }
        if let quality {
            try Self.validateQualityProfile(quality)
        }
        if state.subscriptions.contains(where: {
            $0.feedURL?.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedURL
        }) {
            throw SubscriptionError.duplicateSubscription
        }

        let cleanKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanUnwanted = unwantedKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let subscription = Subscription(
            id: UUID(),
            kind: .feed(url: cleanedURL, title: cleanedTitle, keywords: cleanKeywords, unwantedKeywords: cleanUnwanted),
            quality: quality,
            backfill: backfill,
            paused: false,
            createdAt: now
        )
        state.subscriptions.append(subscription)
        try persist()
        return subscription
    }

    func removeSubscription(id: UUID) throws {
        guard let index = state.subscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound
        }
        state.subscriptions.remove(at: index)
        try persist()
    }

    @discardableResult
    func setSubscriptionPaused(id: UUID, paused: Bool) throws -> Subscription {
        guard let index = state.subscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.subscriptionNotFound
        }
        state.subscriptions[index].paused = paused
        try persist()
        return state.subscriptions[index]
    }

    func updateQualityProfile(_ profile: QualityProfile) throws {
        try Self.validateQualityProfile(profile)
        state.settings.qualityProfile = profile
        try persist()
    }

    private static func validateQualityProfile(_ profile: QualityProfile) throws {
        guard !profile.preferredResolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.maxSizeBytes >= 0,
              profile.topSeedersPoolSize >= 1 else {
            throw SubscriptionError.invalidQualityProfile
        }
    }

    // MARK: - Episode ledger and deduplication

    /// Returns the ledger entry for an episode, if one exists.
    func episodeLedgerEntry(imdbID: String, season: Int, episode: Int) -> EpisodeLedgerEntry? {
        let key = EpisodeLedgerEntry.key(imdbID: imdbID, season: season, episode: episode)
        return state.episodeLedger.first { $0.id == key }
    }

    /// Returns true if Cargo already knows about this episode from any of the
    /// four sources: the episode ledger, the library index, active local jobs,
    /// or live Put.io transfers.
    ///
    /// Reuses `knownMediaIndex(includeTransfers:)` from the background cycle's
    /// duplicate-release check so library, job and transfer matching stay in
    /// one place.
    func isEpisodeKnown(imdbID: String, season: Int, episode: Int) -> Bool {
        let normalizedIMDbID = EpisodeLedgerEntry.normalizeIMDbID(imdbID)
        guard !normalizedIMDbID.isEmpty, season > 0, episode > 0 else { return false }

        // 1. Episode ledger.
        if episodeLedgerEntry(imdbID: normalizedIMDbID, season: season, episode: episode) != nil {
            return true
        }

        let (candidates, matchedLibraryIDs) = showIdentities(for: normalizedIMDbID)

        // 2. Direct library match when TMDB/IMDb metadata links a library item to this IMDb ID.
        if !matchedLibraryIDs.isEmpty,
           state.libraryItems.contains(where: {
               $0.kind == .show && matchedLibraryIDs.contains($0.id) && ($0.episodes[season]?.contains(episode) == true)
           }) {
            return true
        }

        guard !candidates.isEmpty else { return false }

        // 2-4. Library index, active local jobs, and live Put.io transfers via the shared duplicate index.
        let index = knownMediaIndex(includeTransfers: true)
        for candidate in candidates {
            if index.holder(
                forEpisodeOfShow: candidate.title,
                year: candidate.year,
                season: season,
                episode: episode
            ) != nil {
                return true
            }
        }
        return false
    }

    /// Claims an episode in the shared ledger for a subscription source.
    ///
    /// Returns nil when any source (ledger, library, local job, or Put.io
    /// transfer) already knows about the episode, so two sources never start a
    /// duplicate fetch.
    @discardableResult
    func claimEpisode(
        imdbID: String,
        season: Int,
        episode: Int,
        subscriptionID: UUID?,
        state ledgerState: EpisodeLedgerState = .wanted,
        releaseTitle: String? = nil,
        putIOTransferID: Int? = nil,
        airedAt: Date? = nil,
        now: Date = Date()
    ) -> EpisodeLedgerEntry? {
        guard !isEpisodeKnown(imdbID: imdbID, season: season, episode: episode) else {
            return nil
        }
        let entry = EpisodeLedgerEntry(
            imdbID: imdbID,
            season: season,
            episode: episode,
            state: ledgerState,
            subscriptionID: subscriptionID,
            releaseTitle: releaseTitle,
            putIOTransferID: putIOTransferID,
            airedAt: airedAt,
            updatedAt: now,
            attempts: 0,
            nextAttemptAt: nil
        )
        self.state.episodeLedger.append(entry)
        persistQuietly()
        return entry
    }

    /// Creates or updates a ledger entry for an episode and persists state.
    @discardableResult
    func setEpisodeLedgerState(
        imdbID: String,
        season: Int,
        episode: Int,
        state ledgerState: EpisodeLedgerState,
        subscriptionID: UUID? = nil,
        releaseTitle: String? = nil,
        putIOTransferID: Int? = nil,
        airedAt: Date? = nil,
        attempts: Int? = nil,
        nextAttemptAt: Date? = nil,
        now: Date = Date()
    ) throws -> EpisodeLedgerEntry {
        let normalizedIMDbID = EpisodeLedgerEntry.normalizeIMDbID(imdbID)
        guard normalizedIMDbID.hasPrefix("tt"), normalizedIMDbID.count > 2 else {
            throw SubscriptionError.invalidIMDbID
        }
        guard season > 0, episode > 0 else {
            throw SubscriptionError.invalidEpisodeNumber
        }

        let key = EpisodeLedgerEntry.key(imdbID: normalizedIMDbID, season: season, episode: episode)
        if let index = self.state.episodeLedger.firstIndex(where: { $0.id == key }) {
            self.state.episodeLedger[index].state = ledgerState
            if let subscriptionID { self.state.episodeLedger[index].subscriptionID = subscriptionID }
            if let releaseTitle { self.state.episodeLedger[index].releaseTitle = releaseTitle }
            if let putIOTransferID { self.state.episodeLedger[index].putIOTransferID = putIOTransferID }
            if let airedAt { self.state.episodeLedger[index].airedAt = airedAt }
            if let attempts { self.state.episodeLedger[index].attempts = attempts }
            if let nextAttemptAt { self.state.episodeLedger[index].nextAttemptAt = nextAttemptAt }
            self.state.episodeLedger[index].updatedAt = now
            try persist()
            return self.state.episodeLedger[index]
        }

        let entry = EpisodeLedgerEntry(
            imdbID: normalizedIMDbID,
            season: season,
            episode: episode,
            state: ledgerState,
            subscriptionID: subscriptionID,
            releaseTitle: releaseTitle,
            putIOTransferID: putIOTransferID,
            airedAt: airedAt,
            updatedAt: now,
            attempts: attempts ?? 0,
            nextAttemptAt: nextAttemptAt
        )
        self.state.episodeLedger.append(entry)
        try persist()
        return entry
    }

    /// Resolves known `(title, year)` pairs and linked library IDs for an IMDb
    /// ID using only local state (subscriptions, cached TMDB metadata, library
    /// items, and watchlist).
    private func showIdentities(for normalizedIMDbID: String) -> (candidates: [(title: String, year: Int?)], libraryIDs: Set<String>) {
        var candidates: [(title: String, year: Int?)] = []
        var matchedTMDBIDs = Set<Int>()
        var matchedLibraryIDs = Set<String>()

        func appendCandidate(title: String, year: Int?) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = CargoTitleMatch.normalize(trimmed)
            guard !normalized.isEmpty else { return }
            if !candidates.contains(where: { CargoTitleMatch.normalize($0.title) == normalized && $0.year == year }) {
                candidates.append((title: trimmed, year: year))
            }
        }

        for subscription in state.subscriptions {
            if case .series(let subIMDb, let tmdbID, let title, let year) = subscription.kind,
               EpisodeLedgerEntry.normalizeIMDbID(subIMDb) == normalizedIMDbID {
                matchedTMDBIDs.insert(tmdbID)
                appendCandidate(title: title, year: year)
            }
        }

        for (key, meta) in state.metadata {
            let keyMatches = EpisodeLedgerEntry.normalizeIMDbID(key) == normalizedIMDbID
            let imdbMatches = meta.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) == normalizedIMDbID
            let tmdbMatches = matchedTMDBIDs.contains(meta.tmdbID)
            guard keyMatches || imdbMatches || tmdbMatches else { continue }
            matchedTMDBIDs.insert(meta.tmdbID)
            appendCandidate(title: meta.title, year: meta.year)
            if key.hasPrefix("show:") {
                matchedLibraryIDs.insert(key)
            }
        }

        // Second pass catches library items whose metadata matched via a tmdbID learned above.
        if !matchedTMDBIDs.isEmpty {
            for (key, meta) in state.metadata where key.hasPrefix("show:") && matchedTMDBIDs.contains(meta.tmdbID) {
                matchedLibraryIDs.insert(key)
                appendCandidate(title: meta.title, year: meta.year)
            }
        }

        for item in state.libraryItems where item.kind == .show && matchedLibraryIDs.contains(item.id) {
            appendCandidate(title: item.title, year: item.year)
        }

        for item in state.imdbWatchlistItems where EpisodeLedgerEntry.normalizeIMDbID(item.id) == normalizedIMDbID {
            appendCandidate(title: item.title, year: item.year)
        }

        return (candidates, matchedLibraryIDs)
    }
}

// MARK: - UI entry points

// The dashboard calls these. In remote client mode they run on the resident;
// otherwise they change local state like the storage functions above.
extension CargoCoordinator {
    /// The series subscription for an IMDb ID in what the dashboard shows.
    func dashboardSeriesSubscription(imdbID: String?) -> Subscription? {
        guard let imdbID else { return nil }
        let normalized = EpisodeLedgerEntry.normalizeIMDbID(imdbID)
        return dashboardState.subscriptions.first {
            $0.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) == normalized
        }
    }

    /// Poster for a series subscription, from the library or Discover metadata cache.
    func posterURL(for subscription: Subscription) -> URL? {
        guard let imdbID = subscription.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) else { return nil }
        let tmdbID = subscription.tmdbID
        return dashboardState.metadata.values.first {
            $0.mediaType == .tv && ($0.tmdbID == tmdbID || $0.imdbID.map(EpisodeLedgerEntry.normalizeIMDbID) == imdbID)
        }?.posterURL
    }

    func subscribeSeries(imdbID: String, tmdbID: Int, title: String, year: Int?) async throws {
        let command = CargoRemoteCommand.addSeriesSubscription(imdbID: imdbID, tmdbID: tmdbID, title: title, year: year, backfill: nil)
        if try await executeRemoteIfNeeded(command) { return }
        try addSeriesSubscription(imdbID: imdbID, tmdbID: tmdbID, title: title, year: year)
        recordHistory(kind: .info, title: "Subscribed to \(title)", detail: "New episodes only")
    }

    /// Looks the series up on TMDB, then subscribes. TMDB gives the IDs a subscription needs.
    func subscribeSeries(metadata: TMDBMetadata) async throws {
        guard let imdbID = metadata.imdbID, !imdbID.isEmpty else {
            throw SubscriptionError.invalidIMDbID
        }
        try await subscribeSeries(imdbID: imdbID, tmdbID: metadata.tmdbID, title: metadata.title, year: metadata.year)
    }

    func subscribeFeed(url: String, title: String, keywords: [String], unwantedKeywords: [String]) async throws {
        let command = CargoRemoteCommand.addFeedSubscription(
            url: url, title: title, keywords: keywords, unwantedKeywords: unwantedKeywords, backfill: nil
        )
        if try await executeRemoteIfNeeded(command) { return }
        try addFeedSubscription(url: url, title: title, keywords: keywords, unwantedKeywords: unwantedKeywords)
        recordHistory(kind: .info, title: "Subscribed to feed \(title)", detail: "New items only")
    }

    func setSubscriptionPausedFromDashboard(id: UUID, paused: Bool) async throws {
        if try await executeRemoteIfNeeded(.setSubscriptionPaused(id: id, paused: paused)) { return }
        try setSubscriptionPaused(id: id, paused: paused)
    }

    func unsubscribe(id: UUID) async throws {
        if try await executeRemoteIfNeeded(.removeSubscription(id: id)) { return }
        let title = state.subscriptions.first(where: { $0.id == id })?.title
        try removeSubscription(id: id)
        if let title { recordHistory(kind: .info, title: "Unsubscribed from \(title)", detail: "") }
    }
}
