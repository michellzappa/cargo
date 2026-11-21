import CargoRemoteKit
import Foundation
import XCTest
@testable import Cargo

final class SubscriptionTests: XCTestCase {
    // MARK: - Defaults and persistence

    func testRFCDecisionDefaultsMatchSpecification() {
        let profile = QualityProfile.default
        XCTAssertEqual(profile.preferredResolution, "1080p")
        XCTAssertEqual(profile.maxSizeBytes, 4_000_000_000)
        XCTAssertNil(profile.preferredCodec)
        XCTAssertEqual(profile.topSeedersPoolSize, 3)

        let series = Subscription(
            kind: .series(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022)
        )
        XCTAssertEqual(series.backfill, .newOnly)
        XCTAssertFalse(series.paused)
        XCTAssertEqual(series.effectiveQuality(default: profile), profile)

        XCTAssertEqual(SubscriptionDefaults.postAirWaitInterval, 6 * 3600)
        XCTAssertEqual(SubscriptionDefaults.retryWindowInterval, 7 * 86_400)
        XCTAssertEqual(SubscriptionDefaults.minimumChillRequestInterval, 1)
    }

    func testSubscriptionsLedgerAndQualityProfileRoundTripInStateJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoSubscriptionRoundTrip-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_760_003_600)
        let airedAt = Date(timeIntervalSince1970: 1_760_010_000)
        let updatedAt = Date(timeIntervalSince1970: 1_760_031_600)
        let nextAttemptAt = Date(timeIntervalSince1970: 1_760_040_000)

        let seriesID = UUID()
        let feedID = UUID()
        let overrideQuality = QualityProfile(
            preferredResolution: "2160p",
            maxSizeBytes: 8_000_000_000,
            preferredCodec: "x265",
            topSeedersPoolSize: 5
        )
        let seriesSub = Subscription(
            id: seriesID,
            kind: .series(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022),
            quality: overrideQuality,
            backfill: .currentSeason,
            paused: true,
            createdAt: createdAt,
            lastCheckedAt: checkedAt,
            lastError: "Temporary error"
        )
        let feedSub = Subscription(
            id: feedID,
            kind: .feed(
                url: "https://showrss.info/user/42.rss?magnets=true&passkey=secret999",
                title: "showRSS",
                keywords: ["1080p", "WEB"],
                unwantedKeywords: ["CAM", "720p"]
            ),
            quality: nil,
            backfill: .newOnly,
            paused: false,
            createdAt: createdAt,
            lastCheckedAt: nil,
            lastError: nil
        )
        let ledgerEntries: [EpisodeLedgerEntry] = EpisodeLedgerState.allCases.enumerated().map { index, ledgerState in
            EpisodeLedgerEntry(
                imdbID: "tt11280740",
                season: 2,
                episode: index + 1,
                state: ledgerState,
                subscriptionID: index.isMultiple(of: 2) ? seriesID : feedID,
                releaseTitle: "Severance.S02E0\(index + 1).1080p.WEB.h264-GROUP",
                putIOTransferID: ledgerState == .sent || ledgerState == .onPutIO ? 500 + index : nil,
                airedAt: airedAt,
                updatedAt: updatedAt,
                attempts: index,
                nextAttemptAt: ledgerState == .wanted ? nextAttemptAt : nil
            )
        }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.settings.qualityProfile = QualityProfile(
            preferredResolution: "1080p",
            maxSizeBytes: 3_500_000_000,
            preferredCodec: "x264",
            topSeedersPoolSize: 3
        )
        state.subscriptions = [seriesSub, feedSub]
        state.episodeLedger = ledgerEntries
        try store.replace(with: state)

        let reloaded = CargoStore(stateURL: stateURL).snapshot()
        XCTAssertEqual(reloaded.settings.qualityProfile, state.settings.qualityProfile)
        XCTAssertEqual(reloaded.subscriptions, [seriesSub, feedSub])
        XCTAssertEqual(reloaded.episodeLedger, ledgerEntries)
        XCTAssertEqual(reloaded.subscriptions[0].effectiveQuality(default: reloaded.settings.qualityProfile), overrideQuality)
        XCTAssertEqual(reloaded.subscriptions[1].effectiveQuality(default: reloaded.settings.qualityProfile), state.settings.qualityProfile)
    }

    func testLegacyStateFileWithoutSubscriptionFieldsDecodesCleanly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoLegacyState-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacyJSON = #"""
        {
          "transfers": [],
          "localJobs": [],
          "settings": {
            "stagingDirectoryName": "_Inbox",
            "moviesDirectoryName": "Movies",
            "tvShowsDirectoryName": "TV Shows",
            "automaticSyncEnabled": true,
            "automaticOrganizationEnabled": true,
            "notificationsEnabled": true,
            "launchAtLoginEnabled": true,
            "automaticRemoteCleanupEnabled": true,
            "automaticInboxCleanupEnabled": true
          },
          "lastUpdated": "2026-09-21T19:59:00Z"
        }
        """#
        try Data(legacyJSON.utf8).write(to: stateURL)

        let reloaded = CargoStore(stateURL: stateURL).snapshot()
        XCTAssertTrue(reloaded.subscriptions.isEmpty)
        XCTAssertTrue(reloaded.episodeLedger.isEmpty)
        XCTAssertEqual(reloaded.settings.qualityProfile, .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.appendingPathExtension("corrupt").path))
    }

    // MARK: - isEpisodeKnown across all four sources

    @MainActor
    func testIsEpisodeKnownChecksEpisodeLedger() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 3))

        try coordinator.setEpisodeLedgerState(imdbID: "TT11280740", season: 2, episode: 3, state: .sent)
        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 3))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 4))
    }

    @MainActor
    func testIsEpisodeKnownChecksLibraryIndex() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        // Matched via series subscription title + year.
        try coordinator.addSeriesSubscription(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022)
        coordinator.state.libraryItems = [
            LibraryItem(
                id: "show:Severance (2022)",
                kind: .show,
                title: "Severance",
                year: 2022,
                relativePath: "TV Shows/Severance (2022)",
                sizeBytes: 1_000,
                addedAt: Date(),
                episodes: [2: [1, 2]]
            )
        ]

        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 2))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 3))

        // Matched via TMDB metadata link even without a subscription.
        coordinator.state.libraryItems.append(
            LibraryItem(
                id: "show:The Bear (2022)",
                kind: .show,
                title: "The Bear",
                year: 2022,
                relativePath: "TV Shows/The Bear (2022)",
                sizeBytes: 1_000,
                addedAt: Date(),
                episodes: [3: [5]]
            )
        )
        coordinator.state.metadata["show:The Bear (2022)"] = TMDBMetadata(
            tmdbID: 136315,
            mediaType: .tv,
            title: "The Bear",
            year: 2022,
            posterPath: nil,
            overview: nil,
            voteAverage: nil,
            voteCount: nil,
            imdbID: "tt14452776",
            episodeCounts: [3: 10],
            fetchedAt: Date()
        )
        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt14452776", season: 3, episode: 5))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt14452776", season: 3, episode: 6))

        // Conflicting year must not falsely match a remake.
        try coordinator.addSeriesSubscription(imdbID: "tt0407362", tmdbID: 1972, title: "Battlestar Galactica", year: 2004)
        coordinator.state.libraryItems.append(
            LibraryItem(
                id: "show:Battlestar Galactica (1978)",
                kind: .show,
                title: "Battlestar Galactica",
                year: 1978,
                relativePath: "TV Shows/Battlestar Galactica (1978)",
                sizeBytes: 1_000,
                addedAt: Date(),
                episodes: [1: [1]]
            )
        )
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt0407362", season: 1, episode: 1))
    }

    @MainActor
    func testIsEpisodeKnownChecksActiveLocalJobs() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        try coordinator.addSeriesSubscription(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022)

        let inboxFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Severance.S02E05.1080p-\(UUID().uuidString).mkv")
        try Data("x".utf8).write(to: inboxFile)
        defer { try? FileManager.default.removeItem(at: inboxFile) }

        coordinator.state.localJobs = [
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 1,
                name: "Severance.S02E03.1080p.WEB.mkv",
                status: .downloading,
                progress: 0.5,
                destination: nil,
                errorMessage: nil,
                updatedAt: Date()
            ),
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 2,
                name: "Severance.S02E04.1080p.WEB.mkv",
                status: .failed,
                progress: 0,
                destination: nil,
                errorMessage: "Network error",
                updatedAt: Date()
            ),
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 3,
                name: "Severance.S02E05.1080p.WEB.mkv",
                status: .needsReview,
                progress: 1,
                destination: inboxFile.path,
                errorMessage: nil,
                updatedAt: Date()
            ),
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 4,
                name: "Severance.S02E06.1080p.WEB.mkv",
                status: .needsReview,
                progress: 1,
                destination: "/nonexistent/inbox/Severance.S02E06.mkv",
                errorMessage: nil,
                updatedAt: Date()
            )
        ]

        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 3))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 4))
        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 5))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 6))
    }

    @MainActor
    func testIsEpisodeKnownChecksPutIOTransfers() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        try coordinator.addSeriesSubscription(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022)
        coordinator.state.transfers = [
            // Folder/release transfer name without a video file extension.
            RemoteTransfer(
                id: 101,
                name: "Severance.S02E03.1080p.WEB.h264-ETHEL",
                status: .downloading,
                progress: 0.4,
                sizeBytes: 1_500_000_000,
                updatedAt: Date()
            ),
            RemoteTransfer(
                id: 102,
                name: "Severance.S02E04.1080p.WEB.mkv",
                status: .completed,
                progress: 1,
                sizeBytes: 1_500_000_000,
                updatedAt: Date(),
                userFileExists: true
            ),
            RemoteTransfer(
                id: 103,
                name: "Severance.S02E05.1080p.WEB.h264-ETHEL",
                status: .failed,
                progress: 0,
                sizeBytes: 0,
                updatedAt: Date()
            ),
            RemoteTransfer(
                id: 104,
                name: "Severance.S02E06.1080p.WEB.h264-ETHEL",
                status: .cancelled,
                progress: 0,
                sizeBytes: 0,
                updatedAt: Date()
            ),
            RemoteTransfer(
                id: 105,
                name: "Severance.S02E07.1080p.WEB.mkv",
                status: .completed,
                progress: 1,
                sizeBytes: 1_500_000_000,
                updatedAt: Date(),
                userFileExists: false
            )
        ]

        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 3))
        XCTAssertTrue(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 4))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 5))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 6))
        XCTAssertFalse(coordinator.isEpisodeKnown(imdbID: "tt11280740", season: 2, episode: 7))
    }

    @MainActor
    func testSplitDuplicateReleasesReusesSharedIndex() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        coordinator.state.libraryItems = [
            LibraryItem(
                id: "show:Severance (2022)",
                kind: .show,
                title: "Severance",
                year: 2022,
                relativePath: "TV Shows/Severance (2022)",
                sizeBytes: 1_000,
                addedAt: Date(),
                episodes: [2: [1]]
            )
        ]
        let alreadyInLibrary = RemoteFile(id: 1, name: "Severance.S02E01.1080p.mkv", type: .video, parentID: 0, sizeBytes: 2_000, createdAt: Date())
        let smallerRelease = RemoteFile(id: 2, name: "Severance.S02E02.720p.mkv", type: .video, parentID: 0, sizeBytes: 1_000, createdAt: Date())
        let largerRelease = RemoteFile(id: 3, name: "Severance.S02E02.1080p.mkv", type: .video, parentID: 0, sizeBytes: 3_000, createdAt: Date())

        let (wanted, duplicates) = coordinator.splitDuplicateReleases([alreadyInLibrary, smallerRelease, largerRelease])
        XCTAssertEqual(wanted.map(\.id), [3])
        XCTAssertEqual(Set(duplicates.map(\.file.id)), [1, 2])
    }

    // MARK: - Ledger deduplication: two sources, same episode, one fetch

    @MainActor
    func testTwoSourcesSameEpisodeProduceOnlyOneFetchSeriesFirst() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        let seriesSub = try coordinator.addSeriesSubscription(
            imdbID: "tt11280740",
            tmdbID: 95396,
            title: "Severance",
            year: 2022
        )
        let feedSub = try coordinator.addFeedSubscription(
            url: "https://showrss.info/user/42.rss?magnets=true",
            title: "showRSS"
        )

        var fetchCount = 0
        if coordinator.claimEpisode(
            imdbID: "tt11280740",
            season: 2,
            episode: 3,
            subscriptionID: seriesSub.id,
            state: .sent,
            releaseTitle: "Severance.S02E03.1080p.WEB.h264-CHILL"
        ) != nil {
            fetchCount += 1
        }
        if coordinator.claimEpisode(
            imdbID: "tt11280740",
            season: 2,
            episode: 3,
            subscriptionID: feedSub.id,
            state: .sent,
            releaseTitle: "Severance.S02E03.1080p.WEB.h264-FEED"
        ) != nil {
            fetchCount += 1
        }

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(coordinator.state.episodeLedger.count, 1)
        XCTAssertEqual(coordinator.state.episodeLedger.first?.subscriptionID, seriesSub.id)
        XCTAssertEqual(coordinator.state.episodeLedger.first?.releaseTitle, "Severance.S02E03.1080p.WEB.h264-CHILL")
    }

    @MainActor
    func testTwoSourcesSameEpisodeProduceOnlyOneFetchFeedFirst() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        let seriesSub = try coordinator.addSeriesSubscription(
            imdbID: "tt11280740",
            tmdbID: 95396,
            title: "Severance",
            year: 2022
        )
        let feedSub = try coordinator.addFeedSubscription(
            url: "https://showrss.info/user/42.rss?magnets=true",
            title: "showRSS"
        )

        var fetchCount = 0
        if coordinator.claimEpisode(
            imdbID: "tt11280740",
            season: 2,
            episode: 3,
            subscriptionID: feedSub.id,
            state: .sent,
            releaseTitle: "Severance.S02E03.1080p.WEB.h264-FEED"
        ) != nil {
            fetchCount += 1
        }
        if coordinator.claimEpisode(
            imdbID: "tt11280740",
            season: 2,
            episode: 3,
            subscriptionID: seriesSub.id,
            state: .sent,
            releaseTitle: "Severance.S02E03.1080p.WEB.h264-CHILL"
        ) != nil {
            fetchCount += 1
        }

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(coordinator.state.episodeLedger.count, 1)
        XCTAssertEqual(coordinator.state.episodeLedger.first?.subscriptionID, feedSub.id)
    }

    @MainActor
    func testClaimEpisodeSkipsWhenAlreadyInLibraryOrTransfer() throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        let seriesSub = try coordinator.addSeriesSubscription(
            imdbID: "tt11280740",
            tmdbID: 95396,
            title: "Severance",
            year: 2022
        )
        coordinator.state.transfers = [
            RemoteTransfer(
                id: 99,
                name: "Severance.S02E08.1080p.WEB.h264-ETHEL",
                status: .downloading,
                progress: 0.2,
                sizeBytes: 1_000_000_000,
                updatedAt: Date()
            )
        ]

        let claimed = coordinator.claimEpisode(
            imdbID: "tt11280740",
            season: 2,
            episode: 8,
            subscriptionID: seriesSub.id,
            state: .sent
        )
        XCTAssertNil(claimed)
        XCTAssertTrue(coordinator.state.episodeLedger.isEmpty)
    }

    // MARK: - Remote-safe snapshot, passkey stripping, and iOS CargoRemoteKit compatibility

    func testFeedURLSanitizerStripsPasskeysAndKeepsSafeQueryParameters() {
        XCTAssertEqual(
            CargoRemoteLinkSanitizer.sanitizeFeedURL("https://showrss.info/user/12345.rss?magnets=true&quality=hd"),
            "https://showrss.info/user/12345.rss?magnets=true&quality=hd"
        )
        XCTAssertEqual(
            CargoRemoteLinkSanitizer.sanitizeFeedURL("https://tracker.example/rss?passkey=supersecret&cat=tv"),
            "https://tracker.example/rss?cat=tv"
        )
        XCTAssertEqual(
            CargoRemoteLinkSanitizer.sanitizeFeedURL("https://tracker.example/rss?token=secret123&api_key=abc"),
            "https://tracker.example/rss"
        )
        XCTAssertEqual(
            CargoRemoteLinkSanitizer.sanitizeFeedURL("https://tracker.example/rss?p=a1b2c3d4e5f67890a1b2c3d4e5f67890&cat=tv"),
            "https://tracker.example/rss?cat=tv"
        )
        XCTAssertEqual(
            CargoRemoteLinkSanitizer.sanitizeFeedURL("https://alice:hunter2@tracker.example/rss?cat=tv"),
            "https://tracker.example/rss?cat=tv"
        )
    }

    @MainActor
    func testRemoteSnapshotSanitizesFeedURLsAndDecodesInCargoRemoteKit() async throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        let seriesSub = try coordinator.addSeriesSubscription(
            imdbID: "tt11280740",
            tmdbID: 95396,
            title: "Severance",
            year: 2022
        )
        try coordinator.addFeedSubscription(
            url: "https://tracker.example/rss?passkey=TOPSECRETKEY&cat=tv",
            title: "Private Feed",
            keywords: ["1080p"],
            unwantedKeywords: ["cam"]
        )
        try coordinator.setEpisodeLedgerState(
            imdbID: "tt11280740",
            season: 2,
            episode: 3,
            state: .sent,
            subscriptionID: seriesSub.id,
            releaseTitle: "Severance.S02E03.1080p.mkv",
            putIOTransferID: 777
        )

        let controller = CargoRemoteController(coordinator: coordinator)
        let router = CargoRemoteAPIRouter(controller: controller, token: "test-token")

        let stateResponse = await router.handle(
            CargoAPIRequest(method: "GET", uri: "/v1/state", headers: ["authorization": "Bearer test-token"], body: Data())
        )
        XCTAssertEqual(stateResponse.statusCode, 200)
        let stateJSON = String(decoding: stateResponse.body, as: UTF8.self)
        XCTAssertFalse(stateJSON.contains("TOPSECRETKEY"))
        XCTAssertTrue(stateJSON.contains("cat=tv"))

        // Decode the resident's /v1/state response with iOS's CargoRemoteKit types.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let iosEnvelope = try decoder.decode(
            CargoRemoteKit.CargoAPIEnvelope<CargoRemoteKit.CargoRemoteSnapshot>.self,
            from: stateResponse.body
        )
        let iosSnapshot = try XCTUnwrap(iosEnvelope.data)
        XCTAssertEqual(iosSnapshot.subscriptions.count, 2)
        XCTAssertEqual(iosSnapshot.episodeLedger.count, 1)
        XCTAssertEqual(iosSnapshot.episodeLedger.first?.imdbID, "tt11280740")
        XCTAssertEqual(iosSnapshot.episodeLedger.first?.state, .sent)
        XCTAssertEqual(iosSnapshot.qualityProfile?.preferredResolution, "1080p")
        XCTAssertEqual(iosSnapshot.qualityProfile?.maxSizeBytes, 4_000_000_000)

        if case .feed(let sanitizedURL, _, let keywords, let unwanted) = iosSnapshot.subscriptions[1].kind {
            XCTAssertEqual(sanitizedURL, "https://tracker.example/rss?cat=tv")
            XCTAssertEqual(keywords, ["1080p"])
            XCTAssertEqual(unwanted, ["cam"])
        } else {
            XCTFail("Expected second subscription to be a feed")
        }

        // Dedicated GET routes also work.
        let subsResponse = await router.handle(
            CargoAPIRequest(method: "GET", uri: "/v1/subscriptions", headers: ["authorization": "Bearer test-token"], body: Data())
        )
        XCTAssertEqual(subsResponse.statusCode, 200)
        XCTAssertFalse(String(decoding: subsResponse.body, as: UTF8.self).contains("TOPSECRETKEY"))

        let ledgerResponse = await router.handle(
            CargoAPIRequest(method: "GET", uri: "/v1/ledger", headers: ["authorization": "Bearer test-token"], body: Data())
        )
        XCTAssertEqual(ledgerResponse.statusCode, 200)
        XCTAssertTrue(String(decoding: ledgerResponse.body, as: UTF8.self).contains("tt11280740:S02E03"))
    }

    // MARK: - CLI (cargoctl) and MCP (CargoMCP)

    @MainActor
    func testCLISubscriptionAndLedgerCommandsDriveResidentAPI() async throws {
        let (coordinator, cleanup) = try makeCoordinator()
        defer { cleanup() }

        let controller = CargoRemoteController(coordinator: coordinator)
        let router = CargoRemoteAPIRouter(controller: controller, token: "test-token")

        let addSeries = try CargoCLI.parseSubscriptionCommand([
            "add-series", "tt11280740", "95396", "Severance", "--year", "2022", "--backfill", "currentSeason"
        ])
        let addFeed = try CargoCLI.parseSubscriptionCommand([
            "add-feed", "https://tracker.example/rss?passkey=SECRET&cat=tv", "My", "Feed",
            "--keyword", "1080p", "--unwanted", "cam"
        ])
        let setLedger = try CargoCLI.parseLedgerCommand(["set", "tt11280740", "2", "3", "skipped"])

        for command in [addSeries, addFeed, setLedger] {
            let body = try JSONEncoder().encode(command)
            let response = await router.handle(
                CargoAPIRequest(
                    method: "POST",
                    uri: "/v1/commands",
                    headers: ["authorization": "Bearer test-token"],
                    body: body
                )
            )
            XCTAssertEqual(response.statusCode, 200)
        }

        XCTAssertEqual(coordinator.state.subscriptions.count, 2)
        let addedSeries = try XCTUnwrap(coordinator.state.subscriptions.first)
        XCTAssertEqual(addedSeries.backfill, .currentSeason)
        XCTAssertEqual(coordinator.episodeLedgerEntry(imdbID: "tt11280740", season: 2, episode: 3)?.state, .skipped)

        // Pause and remove via CLI parsers.
        let pause = try CargoCLI.parseSubscriptionCommand(["pause", addedSeries.id.uuidString])
        let pauseResponse = await router.handle(
            CargoAPIRequest(
                method: "POST",
                uri: "/v1/commands",
                headers: ["authorization": "Bearer test-token"],
                body: try JSONEncoder().encode(pause)
            )
        )
        XCTAssertEqual(pauseResponse.statusCode, 200)
        XCTAssertTrue(coordinator.state.subscriptions.first(where: { $0.id == addedSeries.id })?.paused == true)

        let remove = try CargoCLI.parseSubscriptionCommand(["remove", addedSeries.id.uuidString])
        let removeResponse = await router.handle(
            CargoAPIRequest(
                method: "POST",
                uri: "/v1/commands",
                headers: ["authorization": "Bearer test-token"],
                body: try JSONEncoder().encode(remove)
            )
        )
        XCTAssertEqual(removeResponse.statusCode, 200)
        XCTAssertEqual(coordinator.state.subscriptions.count, 1)
    }

    func testMCPExposesSubscriptionsAndLedgerThroughCLI() throws {
        XCTAssertTrue(CargoMCP.toolNames.contains("cargo_subscriptions"))
        XCTAssertTrue(CargoMCP.toolNames.contains("cargo_ledger"))

        XCTAssertEqual(
            try CargoMCP.cliArguments(forTool: "cargo_list", input: ["list": "subscriptions", "grep": "Severance"]),
            ["subscriptions", "--grep", "Severance"]
        )
        XCTAssertEqual(
            try CargoMCP.cliArguments(forTool: "cargo_list", input: ["list": "ledger", "limit": 5]),
            ["ledger", "--limit", "5"]
        )
        let seriesArgs = try CargoMCP.cliArguments(
            forTool: "cargo_subscriptions",
            input: ["action": "add_series", "imdb_id": "tt11280740", "tmdb_id": 95396, "title": "Severance", "year": 2022]
        )
        XCTAssertEqual(seriesArgs, ["subscriptions", "add-series", "tt11280740", "95396", "Severance", "--year", "2022"])
        XCTAssertEqual(
            try CargoCLI.parseSubscriptionCommand(Array(seriesArgs.dropFirst())),
            .addSeriesSubscription(imdbID: "tt11280740", tmdbID: 95396, title: "Severance", year: 2022, backfill: nil)
        )

        let feedArgs = try CargoMCP.cliArguments(
            forTool: "cargo_subscriptions",
            input: [
                "action": "add_feed",
                "url": "https://showrss.info/user/42.rss",
                "title": "showRSS",
                "keywords": ["1080p"],
                "unwanted_keywords": ["cam"]
            ]
        )
        XCTAssertEqual(
            try CargoCLI.parseSubscriptionCommand(Array(feedArgs.dropFirst())),
            .addFeedSubscription(
                url: "https://showrss.info/user/42.rss",
                title: "showRSS",
                keywords: ["1080p"],
                unwantedKeywords: ["cam"],
                backfill: nil
            )
        )

        let ledgerArgs = try CargoMCP.cliArguments(
            forTool: "cargo_ledger",
            input: ["action": "set", "imdb_id": "tt11280740", "season": 2, "episode": 3, "state": "skipped"]
        )
        XCTAssertEqual(
            try CargoCLI.parseLedgerCommand(Array(ledgerArgs.dropFirst())),
            .setEpisodeLedgerState(imdbID: "tt11280740", season: 2, episode: 3, state: .skipped)
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeCoordinator() throws -> (CargoCoordinator, () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoSubTests-\(UUID().uuidString)", isDirectory: true)
        let store = CargoStore(stateURL: directory.appendingPathComponent("state.json"))
        let coordinator = CargoCoordinator(
            store: store,
            client: UnconfiguredPutIOClient(),
            chillClient: UnconfiguredChillClient()
        )
        return (coordinator, { try? FileManager.default.removeItem(at: directory) })
    }
}
