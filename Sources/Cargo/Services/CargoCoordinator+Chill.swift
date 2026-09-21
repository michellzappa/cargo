import Foundation

// Chill Institute: token, catalog, search, handoff to Put.io.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    func saveChillToken(_ token: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw ChillAPIClient.ClientError.missingToken
        }

        try keychain.saveChillToken(trimmedToken)
        chillClient = ChillAPIClient(token: trimmedToken)
        chillStatus = "Token saved · testing…"
    }

    func verifyChillConnection() async {
        do {
            let profile = try await chillClient.fetchProfile()
            let displayName = profile.username.isEmpty ? profile.userID : profile.username
            chillStatus = "Connected as \(displayName)"
            Task { await refreshChillCatalog() }
        } catch {
            if chillClient is UnconfiguredChillClient {
                chillStatus = "Not connected yet"
            } else {
                chillStatus = "Chill error · \(error.localizedDescription)"
            }
        }
    }

    func removeChillToken() throws {
        try keychain.deleteChillToken()
        chillClient = UnconfiguredChillClient()
        chillSearchQuery = ""
        chillSearchResults = []
        chillSearchStatus = "Search Chill for a release"
        chillCatalogMovies = []
        chillCatalogShows = []
        chillCatalogStatus = "Top movies and series appear here"
        chillStatus = "Not connected yet"
    }

    func searchChill(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        chillSearchQuery = trimmedQuery
        guard !trimmedQuery.isEmpty else {
            chillSearchResults = []
            chillSearchStatus = "Enter a title, show, or release"
            return
        }
        chillSearchStatus = "Searching Chill…"
        do {
            if isRemoteClientMode {
                let remote = try await remoteClientSession.search(query: trimmedQuery)
                chillSearchResults = remote.results.map(ChillSearchResult.init)
                chillSearchStatus = remote.status
            } else {
                chillSearchResults = try await chillReleases(matching: trimmedQuery)
                chillSearchStatus = "\(chillSearchResults.count) result\(chillSearchResults.count == 1 ? "" : "s")"
            }
        } catch {
            chillSearchResults = []
            chillSearchStatus = error.localizedDescription
        }
    }

    /// The stateless core of a Chill search, shared by this Mac's Discover
    /// page and by remote clients searching through the resident.
    func chillReleases(matching query: String) async throws -> [ChillSearchResult] {
        if !isChillConnected, chillStatus.hasPrefix("Token saved") {
            await verifyChillConnection()
        }
        guard isChillConnected else {
            throw ChillAPIClient.ClientError.requestFailed("Connect Chill in Settings → Chill")
        }
        return try await chillClient.search(query: query)
            .sorted {
                if $0.seeders != $1.seeders { return $0.seeders > $1.seeders }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func refreshChillCatalog() async {
        if isRemoteClientMode {
            _ = try? await remoteClientSession.execute(.refreshChillCatalog)
            return
        }
        guard isChillConnected else {
            chillCatalogMovies = []
            chillCatalogShows = []
            chillCatalogStatus = "Connect Chill in Settings → Chill"
            return
        }

        chillCatalogStatus = "Loading top movies and series…"
        do {
            async let movies = fetchExpandedMovies()
            async let shows = fetchExpandedTVShows()
            chillCatalogMovies = try await movies
            chillCatalogShows = try await shows
            let movieCount = chillCatalogMovies.count
            let showCount = chillCatalogShows.count
            chillCatalogStatus = "\(movieCount) movies · \(showCount) series"
        } catch {
            chillCatalogMovies = []
            chillCatalogShows = []
            chillCatalogStatus = error.localizedDescription
        }
    }

    /// Chill's aggregated movie catalog is intentionally short. Ask each
    /// chart for its own catalog in parallel, then keep the first copy of
    /// each title so the Discover page has a useful tail.
    func fetchExpandedMovies() async throws -> [ChillMovie] {
        let client = chillClient
        let sources = ChillMovieCatalogSource.allCases
        let batches = await withTaskGroup(of: (Int, [ChillMovie]?).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    (index, try? await client.fetchMovies(source: source))
                }
            }

            var results = Array(repeating: [ChillMovie](), count: sources.count)
            for await (index, movies) in group {
                results[index] = movies ?? []
            }
            return results
        }

        var seen = Set<String>()
        let expanded = batches.flatMap { $0 }.filter { movie in
            let title = movie.displayTitle
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let key = title.isEmpty ? "id:\(movie.id)" : "\(title)|\(movie.year)"
            return seen.insert(key).inserted
        }
        if !expanded.isEmpty { return expanded }

        // Preserve the previous aggregated behavior if the source-specific
        // endpoint is unavailable for this account or API deployment.
        return try await client.fetchMovies()
    }

    /// Chill's aggregated TV catalog is intentionally short. Ask each
    /// provider for its own catalog in parallel, then keep the first copy of
    /// each IMDb title so the provider/network filters have a useful tail.
    func fetchExpandedTVShows() async throws -> [ChillTVShow] {
        let client = chillClient
        let sources = ChillTVCatalogSource.allCases
        let batches = await withTaskGroup(of: (Int, [ChillTVShow]?).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    (index, try? await client.fetchTVShows(source: source))
                }
            }

            var results = Array(repeating: [ChillTVShow](), count: sources.count)
            for await (index, shows) in group {
                results[index] = shows ?? []
            }
            return results
        }

        var seen = Set<String>()
        let expanded = batches.flatMap { $0 }.filter { show in
            seen.insert(show.id).inserted
        }
        if !expanded.isEmpty { return expanded }

        // Preserve the previous aggregated behavior if a provider-specific
        // endpoint is unavailable for this account or API deployment.
        return try await client.fetchTVShows()
    }

    func requestChillSearch(query: String) {
        chillSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        chillSearchResults = []
        chillSearchStatus = chillSearchQuery.isEmpty ? "Enter a title, show, or release" : "Ready to search"
        NotificationCenter.default.post(name: Self.didRequestChillSearch, object: self)
    }

    func sendChillResult(_ result: ChillSearchResult) async throws {
        if try await executeRemoteIfNeeded(.sendChillRelease(url: result.link, title: result.releaseTitle)) { return }
        try await sendChillTransfer(url: result.link, title: result.releaseTitle)
    }

    func sendChillRelease(url: String, title: String?) async throws {
        try await sendChillTransfer(url: url, title: title)
    }

    func sendChillMovie(_ movie: ChillMovie) async throws {
        if try await executeRemoteIfNeeded(.sendChillMovie(id: movie.id)) { return }
        try await sendChillTransfer(url: movie.link, title: movie.displayTitle)
    }

    func sendChillEpisode(imdbID: String, season: Int, episode: Int) async throws {
        guard let download = try await chillClient.episodeDownload(
            imdbID: imdbID,
            season: season,
            episode: episode
        ) else {
            throw ChillAPIClient.ClientError.requestFailed("Chill did not find a download for this episode.")
        }
        try await sendChillTransfer(url: download.link, title: download.title)
    }

    func sendChillTransfer(url: String, title: String?) async throws {
        guard isConnected else {
            throw UnconfiguredPutIOClient.ClientError.notConfigured
        }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
            throw SettingsError.invalidTransferURL
        }
        let response = try await chillClient.addTransfer(url: trimmedURL)
        let name = title ?? response.transfer?.name ?? trimmedURL
        recordHistory(kind: .info, title: "Added via Chill", detail: name)
        await refreshFromPutIO(force: false)
    }
}
