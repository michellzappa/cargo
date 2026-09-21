import Foundation

// Library scan, TMDB/OMDb metadata, completeness.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    // MARK: - Library

    var hasTMDBKey: Bool { !(keychain.readTMDBKey() ?? "").isEmpty }
    var hasOMDBKey: Bool { !(keychain.readOMDBKey() ?? "").isEmpty }

    func saveTMDBKey(_ key: String) throws {
        try keychain.saveTMDBKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        discoverMetadata.removeAll()
        scheduleChangeNotification()
    }

    func saveOMDBKey(_ key: String) throws {
        try keychain.saveOMDBKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        scheduleChangeNotification()
    }

    /// Looks up a Discover title on demand. Library enrichment remains persisted
    /// in CargoState; this cache is intentionally session-only because Discover
    /// titles are supplied by Chill and may change between catalog refreshes.
    func fetchDiscoverMetadata(
        title: String,
        year: Int?,
        type: TMDBMetadata.MediaType,
        imdbID: String?
    ) async throws -> TMDBMetadata {
        guard let key = keychain.readTMDBKey(), !key.isEmpty else {
            throw TMDBClient.ClientError.missingKey
        }
        let cacheKey = [type.rawValue, imdbID ?? "", title, year.map(String.init) ?? ""].joined(separator: "|")
        if let cached = discoverMetadata[cacheKey] { return cached }
        let client = TMDBClient(apiKey: key)
        let metadata: TMDBMetadata
        if let imdbID, imdbID.hasPrefix("tt") {
            metadata = try await client.find(imdbID: imdbID)
        } else {
            metadata = try await client.search(title: title, year: year, type: type)
        }
        discoverMetadata[cacheKey] = metadata
        return metadata
    }

    func fetchDiscoverRatings(imdbID: String) async throws -> OMDBRatings {
        guard let key = keychain.readOMDBKey(), !key.isEmpty else {
            throw OMDBClient.ClientError.missingKey
        }
        if let cached = discoverRatingsCache.ratings(for: imdbID) { return cached }
        let ratings = try await OMDBClient(apiKey: key).ratings(imdbID: imdbID)
        discoverRatingsCache.store(ratings, for: imdbID)
        return ratings
    }


    /// Rescans the SSD. Cheap — directory listings only — so it runs every cycle.
    func scanLibrary() {
        guard let root = libraryRootURL() else { return }
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let items = LibraryIndex.scan(root: root, settings: state.settings)
        guard items != state.libraryItems else { return }
        state.libraryItems = items
        persistQuietly()
    }

    /// Library item for a watchlist entry: by TMDB id when both sides have
    /// metadata, else by title and year.
    func libraryItem(for watchlistItem: IMDbWatchlistItem) -> LibraryItem? {
        if let meta = state.metadata[watchlistItem.id] {
            if let hit = state.libraryItems.first(where: { state.metadata[$0.id]?.tmdbID == meta.tmdbID }) { return hit }
        }
        let wanted = Self.normalizedTitle(watchlistItem.title)
        return state.libraryItems.first {
            Self.normalizedTitle($0.title) == wanted && (watchlistItem.year == nil || $0.year == nil || $0.year == watchlistItem.year)
        }
    }

    static func normalizedTitle(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Fills in TMDB metadata for library and watchlist entries that lack it
    /// or whose copy is a week old — a handful per cycle, to stay polite.
    func enrichMetadata(limit: Int = 40) async {
        guard let key = keychain.readTMDBKey(), !key.isEmpty else { return }
        let client = TMDBClient(apiKey: key)
        var budget = limit
        var changed = false

        func needsLookup(_ id: String) -> Bool {
            if let existing = state.metadata[id], !existing.isStale { return false }
            if let missed = state.metadataMisses[id], Date().timeIntervalSince(missed) < 7 * 86_400 { return false }
            return true
        }
        func store(_ id: String, _ lookup: () async throws -> TMDBMetadata) async -> Bool {
            budget -= 1
            do {
                state.metadata[id] = try await lookup()
                state.metadataMisses[id] = nil
                return true
            } catch TMDBClient.ClientError.notFound {
                state.metadataMisses[id] = Date()
                return true
            } catch {
                // Network or key trouble: stop for this cycle rather than burn the budget.
                budget = 0
                tmdbStatus = error.localizedDescription
                return false
            }
        }

        for item in state.libraryItems where budget > 0 && needsLookup(item.id) {
            let kind: TMDBMetadata.MediaType = item.kind == .movie ? .movie : .tv
            changed = await store(item.id) { try await client.search(title: item.title, year: item.year, type: kind) } || changed
        }
        for item in state.imdbWatchlistItems where budget > 0 && item.id.hasPrefix("tt") && needsLookup(item.id) {
            changed = await store(item.id) { try await client.find(imdbID: item.id) } || changed
        }
        if changed { persistQuietly() }
    }


    /// Forget misses so the next cycle tries them again (after a rename, say).
    func retryMetadataMisses() {
        state.metadataMisses.removeAll()
        persistQuietly()
        Task { await enrichMetadata() }
    }

    /// Season → episode numbers TMDB says exist but the disk lacks.
    func missingEpisodes(for item: LibraryItem) -> [Int: [Int]] {
        guard item.kind == .show, let counts = state.metadata[item.id]?.episodeCounts else { return [:] }
        var missing: [Int: [Int]] = [:]
        for (season, count) in counts where count > 0 {
            // Only seasons the library has started; unaired future seasons are noise.
            guard let have = item.episodes[season] else { continue }
            let gaps = (1...count).filter { !have.contains($0) }
            if !gaps.isEmpty { missing[season] = gaps }
        }
        return missing
    }

    /// Searches Put.io for the show and queues any video whose name carries a
    /// missing SxxEyy. Returns what was queued and what is still missing.
    func findMissingOnPutIO(for item: LibraryItem) async throws -> (queued: [String], stillMissing: Int) {
        let missing = missingEpisodes(for: item)
        let wanted = Set(missing.flatMap { season, episodes in episodes.map { String(format: "S%02dE%02d", season, $0) } })
        guard !wanted.isEmpty else { return ([], 0) }
        let results = try await putIOClient.searchFiles(query: item.title)
        var queued: [String] = []
        var found = Set<String>()
        for file in results where file.isMediaFile {
            guard let (season, episode) = LibraryIndex.seasonEpisode(from: file.name) else { continue }
            let marker = String(format: "S%02dE%02d", season, episode)
            guard wanted.contains(marker), !found.contains(marker) else { continue }
            found.insert(marker)
            var remote = file
            remote.path = file.name
            enqueueLocalSync(remoteFile: remote)
            queued.append(file.name)
        }
        if !queued.isEmpty {
            recordHistory(kind: .info, title: "Queued from Put.io search", detail: "\(item.displayTitle): \(queued.joined(separator: ", "))")
            Task { await runBackgroundCycle() }
        }
        return (queued, wanted.count - found.count)
    }

    func deleteLibraryItem(_ item: LibraryItem) throws {
        guard let root = libraryRootURL() else { throw SettingsError.libraryRootMissing }
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let url = root.appendingPathComponent(item.relativePath)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        state.libraryItems.removeAll { $0.id == item.id }
        try persist()
        recordHistory(kind: .success, title: "Moved to Trash", detail: item.displayTitle)
        scanLibrary()
    }
}
