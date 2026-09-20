import Foundation
import XCTest
@testable import Cargo

final class CargoTests: XCTestCase {
    func testChillModelsDecodeProtoJSONShape() throws {
        let resultData = Data(#"""
        {
          "id": "release-1",
          "title": "The Bear S03E02 1080p",
          "indexer": "example",
          "link": "magnet:?xt=urn:btih:release",
          "imdbId": "tt14452776",
          "peers": "3",
          "seeders": "42",
          "size": "1234567890",
          "releaseInfo": {
            "title": "The Bear",
            "year": 2024,
            "season": 3,
            "episode": 2,
            "resolution": "1080p",
            "codec": "x265"
          }
        }
        """#.utf8)

        let result = try JSONDecoder().decode(ChillSearchResult.self, from: resultData)
        XCTAssertEqual(result.seeders, 42)
        XCTAssertEqual(result.size, 1_234_567_890)
        XCTAssertEqual(result.releaseInfo?.season, 3)
        XCTAssertEqual(result.releaseInfo?.episode, 2)
        XCTAssertEqual(result.releaseTitle, "The Bear")

        let episodeData = Data(#"""
        {
          "title": "The Bear S03E02",
          "link": "magnet:?xt=urn:btih:episode",
          "size": "987654321",
          "seeders": "18",
          "seasonNumber": 3,
          "episodeNumber": 2
        }
        """#.utf8)
        let episode = try JSONDecoder().decode(ChillEpisodeDownload.self, from: episodeData)
        XCTAssertEqual(episode.size, 987_654_321)
        XCTAssertEqual(episode.seeders, 18)
        XCTAssertEqual(episode.seasonNumber, 3)
        XCTAssertEqual(episode.episodeNumber, 2)
    }

    func testChillCatalogModelsDecodeProtoJSONShape() throws {
        let movies = Data(#"""
        {
          "movies": [{
            "id": "movie-1",
            "title": "Arrival",
            "year": 2016,
            "titlePretty": "Arrival (2016)",
            "link": "magnet:?xt=urn:btih:movie",
            "peers": "12",
            "seeders": "8",
            "size": "2345678901",
            "posterUrl": "https://image.example/poster.jpg",
            "rating": 7.9,
            "externalUrl": "https://www.imdb.com/title/tt2543164/",
            "genres": ["Drama", "Science Fiction"]
          }]
        }
        """#.utf8)
        let movieResponse = try JSONDecoder().decode(CatalogMoviesEnvelope.self, from: movies)
        XCTAssertEqual(movieResponse.movies.first?.displayTitle, "Arrival (2016)")
        XCTAssertEqual(movieResponse.movies.first?.seeders, 8)
        XCTAssertEqual(movieResponse.movies.first?.size, 2_345_678_901)
        XCTAssertEqual(movieResponse.movies.first?.genres, ["Drama", "Science Fiction"])

        let shows = Data(#"""
        {
          "shows": [{
            "imdbId": "tt0903747",
            "title": "Breaking Bad",
            "year": 2008,
            "posterUrl": "https://image.example/show.jpg",
            "rating": 8.9,
            "seasonCount": 5,
            "status": 2,
            "networks": ["AMC"]
          }]
        }
        """#.utf8)
        let showResponse = try JSONDecoder().decode(CatalogShowsEnvelope.self, from: shows)
        XCTAssertEqual(showResponse.shows.first?.id, "tt0903747")
        XCTAssertEqual(showResponse.shows.first?.displayTraits, "2008 · 8.9 ★ · 5 seasons · Ended")
        XCTAssertEqual(showResponse.shows.first?.networks, ["AMC"])
    }

    private struct CatalogMoviesEnvelope: Decodable { let movies: [ChillMovie] }
    private struct CatalogShowsEnvelope: Decodable { let shows: [ChillTVShow] }

    func testStateRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.transfers = [
            RemoteTransfer(
                id: 1001,
                name: "Roundtrip Episode",
                status: .downloading,
                progress: 0.5,
                sizeBytes: 1_000,
                updatedAt: Date()
            ),
            RemoteTransfer(
                id: 1002,
                name: "Roundtrip Movie",
                status: .completed,
                progress: 1,
                sizeBytes: 2_000,
                updatedAt: Date()
            )
        ]
        state.remoteFiles = [
            RemoteFile(
                id: 2001,
                name: "Roundtrip Movie.mkv",
                type: .video,
                parentID: 0,
                sizeBytes: 2_000,
                createdAt: Date()
            ),
            RemoteFile(
                id: 2002,
                name: "Roundtrip Shows",
                type: .folder,
                parentID: 0,
                sizeBytes: 0,
                createdAt: Date()
            )
        ]
        state.localJobs = [
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 1002,
                name: "Roundtrip Movie",
                status: .queued,
                progress: 0,
                destination: nil,
                errorMessage: nil,
                updatedAt: Date()
            )
        ]
        state.history = [
            CargoHistoryEntry(
                id: UUID(),
                date: Date(),
                kind: .success,
                title: "Downloaded",
                detail: "Roundtrip Movie"
            )
        ]
        state.remoteMediaFiles = [state.remoteFiles[0]]
        state.remoteFolders = [state.remoteFiles[1]]
        let watchlistAddedAt = Date(timeIntervalSince1970: 1_735_689_600)
        state.imdbWatchlistItems = [
            IMDbWatchlistItem(
                id: "tt1234567",
                title: "Roundtrip Movie",
                year: 2026,
                titleType: "movie",
                addedAt: watchlistAddedAt
            )
        ]
        state.imdbWatchlistLastUpdated = Date()
        state.deletedRemoteFileIDs = [2001]
        state.seenRemoteMediaFileIDs = [2001]
        state.remoteMediaBaselineEstablished = true
        state.settings = CargoSettings(
            automaticSyncEnabled: false,
            automaticOrganizationEnabled: true,
            notificationsEnabled: false,
            launchAtLoginEnabled: false
        )
        try store.replace(with: state)

        XCTAssertEqual(store.snapshot().transfers.count, 2)

        let reloaded = CargoStore(stateURL: stateURL)
        XCTAssertEqual(reloaded.snapshot().transfers.map(\.id), [1001, 1002])
        XCTAssertEqual(reloaded.snapshot().remoteFiles.count, 2)
        XCTAssertEqual(reloaded.snapshot().localJobs.count, 1)
        XCTAssertEqual(reloaded.snapshot().history.count, 1)
        XCTAssertEqual(reloaded.snapshot().remoteMediaFiles.map(\.id), [2001])
        XCTAssertEqual(reloaded.snapshot().imdbWatchlistItems.map(\.id), ["tt1234567"])
        XCTAssertEqual(reloaded.snapshot().imdbWatchlistItems.first?.year, 2026)
        XCTAssertEqual(reloaded.snapshot().imdbWatchlistItems.first?.addedAt, watchlistAddedAt)
        XCTAssertNotNil(reloaded.snapshot().imdbWatchlistLastUpdated)
        XCTAssertEqual(reloaded.snapshot().deletedRemoteFileIDs, [2001])
        XCTAssertEqual(reloaded.snapshot().remoteFolders.map(\.id), [2002])
        XCTAssertEqual(reloaded.snapshot().seenRemoteMediaFileIDs, [2001])
        XCTAssertTrue(reloaded.snapshot().remoteMediaBaselineEstablished)
        XCTAssertFalse(reloaded.snapshot().settings.automaticSyncEnabled)
        XCTAssertTrue(reloaded.snapshot().settings.automaticOrganizationEnabled)
        XCTAssertFalse(reloaded.snapshot().settings.notificationsEnabled)
        XCTAssertFalse(reloaded.snapshot().settings.launchAtLoginEnabled)
        XCTAssertTrue(reloaded.snapshot().settings.automaticRemoteCleanupEnabled)
        XCTAssertTrue(reloaded.snapshot().settings.automaticInboxCleanupEnabled)
    }

    func testStatusesHaveHumanReadableNames() {
        XCTAssertEqual(RemoteTransferStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(LocalSyncStatus.needsReview.displayName, "In inbox · awaiting organization")
    }

    func testRemoteCommandsRoundTripAsStableJSON() throws {
        let commands: [CargoRemoteCommand] = [
            .refresh,
            .refreshChillCatalog,
            .searchChill(query: "The Bear 2024"),
            .sendChillResult(id: "release-1"),
            .sendChillMovie(id: "movie-1"),
            .addTransfer(url: "magnet:?xt=urn:btih:release"),
            .cancelTransfer(id: 42),
            .retryTransfer(id: 43),
            .enqueueLocalSync(remoteFileID: 99),
            .organizeLocalJob(id: UUID()),
            .refreshWatchlist
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for command in commands {
            let data = try encoder.encode(command)
            XCTAssertEqual(try decoder.decode(CargoRemoteCommand.self, from: data), command)
        }
    }

    @MainActor
    func testRemoteSnapshotDoesNotExposeLocalSecretsOrAbsolutePaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoRemoteTests-\(UUID().uuidString)", isDirectory: true)
        let store = CargoStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        var state = store.snapshot()
        state.settings = CargoSettings(
            libraryRootBookmark: Data("SECURITY-SCOPED-BOOKMARK".utf8),
            libraryRootPath: "/Users/example/Media Library",
            openSubtitlesUsername: "subtitle-user",
            openSubtitlesAPIKey: "subtitle-secret"
        )
        state.localJobs = [
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 100,
                name: "Movie.mkv",
                status: .failed,
                progress: 0.4,
                destination: "/Users/example/Media Library/_Inbox/Movie.mkv",
                errorMessage: "Could not read /Users/example/Media Library/_Inbox/Movie.mkv",
                updatedAt: Date()
            )
        ]
        state.libraryItems = [
            LibraryItem(
                id: "movie:Arrival (2016)",
                kind: .movie,
                title: "Arrival",
                year: 2016,
                relativePath: "Movies/Arrival (2016).mkv",
                sizeBytes: 100,
                addedAt: Date(),
                episodes: [:]
            )
        ]
        try store.replace(with: state)

        let controller = CargoRemoteController(coordinator: CargoCoordinator(store: store))
        let data = try JSONEncoder().encode(controller.snapshot())
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("SECURITY-SCOPED-BOOKMARK"))
        XCTAssertFalse(json.contains("/Users/example/Media Library"))
        XCTAssertFalse(json.contains("subtitle-user"))
        XCTAssertFalse(json.contains("subtitle-secret"))
        XCTAssertTrue(json.contains("Movies/Arrival (2016).mkv"))
    }

    @MainActor
    func testRemoteAPIRequiresBearerTokenAndUsesStableEnvelopes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoAPITests-\(UUID().uuidString)", isDirectory: true)
        let store = CargoStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        var state = store.snapshot()
        state.settings = CargoSettings(
            libraryRootBookmark: Data("BOOKMARK".utf8),
            libraryRootPath: "/Users/example/Library",
            openSubtitlesAPIKey: "secret"
        )
        try store.replace(with: state)

        let controller = CargoRemoteController(coordinator: CargoCoordinator(store: store))
        let router = CargoRemoteAPIRouter(controller: controller, token: "test-token")

        let unauthorized = await router.handle(
            CargoAPIRequest(method: "GET", uri: "/v1/health", headers: [:], body: Data())
        )
        XCTAssertEqual(unauthorized.statusCode, 401)
        XCTAssertTrue(String(decoding: unauthorized.body, as: UTF8.self).contains("\"ok\":false"))

        let health = await router.handle(
            CargoAPIRequest(
                method: "GET",
                uri: "/v1/health",
                headers: ["authorization": "Bearer test-token"],
                body: Data()
            )
        )
        XCTAssertEqual(health.statusCode, 200)
        let healthJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: health.body) as? [String: Any]
        )
        XCTAssertEqual(healthJSON["ok"] as? Bool, true)
        XCTAssertNotNil(healthJSON["requestID"] as? String)
        XCTAssertEqual(
            (healthJSON["data"] as? [String: Any])?["apiVersion"] as? String,
            "v1"
        )

        let stateResponse = await router.handle(
            CargoAPIRequest(
                method: "GET",
                uri: "/v1/state",
                headers: ["authorization": "Bearer test-token"],
                body: Data()
            )
        )
        let stateJSON = String(decoding: stateResponse.body, as: UTF8.self)
        XCTAssertEqual(stateResponse.statusCode, 200)
        XCTAssertFalse(stateJSON.contains("BOOKMARK"))
        XCTAssertFalse(stateJSON.contains("/Users/example/Library"))
        XCTAssertFalse(stateJSON.contains("secret"))

        let searchBody = try JSONEncoder().encode(CargoAPISearchRequest(query: "Arrival 2016"))
        let search = await router.handle(
            CargoAPIRequest(
                method: "POST",
                uri: "/v1/discover/search",
                headers: ["authorization": "Bearer test-token"],
                body: searchBody
            )
        )
        XCTAssertEqual(search.statusCode, 200)
        let searchJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: search.body) as? [String: Any]
        )
        XCTAssertEqual(searchJSON["ok"] as? Bool, true)
        XCTAssertEqual(
            (searchJSON["data"] as? [String: Any])?["query"] as? String,
            "Arrival 2016"
        )
    }

    func testRemoteProjectionDoesNotExposeTokenizedLinks() throws {
        let result = try JSONDecoder().decode(
            ChillSearchResult.self,
            from: Data(#"{"id":"1","title":"Arrival","indexer":"test","link":"https://api.chill.institute/download/test?download_token=secret","peers":1,"seeders":2,"size":3,"source":"test","uploadedAt":"2026-01-01T00:00:00Z"}"#.utf8)
        )

        XCTAssertEqual(CargoRemoteSearchResult(result).link, "")
    }

    func testRemoteHTTPServerStartsAndStopsCleanly() throws {
        let server = CargoHTTPServer(
            configuration: .init(host: "127.0.0.1", port: 0)
        ) { _ in
            CargoAPIResponse(
                statusCode: 200,
                requestID: UUID().uuidString,
                body: Data(#"{"ok":true}"#.utf8)
            )
        }
        try server.start()
        XCTAssertNotNil(server.localAddress?.port)
        server.stop()
        server.stop()
    }

    func testLibraryOrganizerPreviewsMovieAndTVDestinations() {
        let settings = CargoSettings(
            stagingDirectoryName: ".inbox",
            moviesDirectoryName: "Films",
            tvShowsDirectoryName: "Series"
        )

        let movie = LibraryOrganizer.preview(for: "Arrival.2016.1080p.mkv", settings: settings)
        XCTAssertEqual(movie.kind, .movie)
        XCTAssertEqual(movie.relativePath, "Films/Arrival (2016).mkv")

        let episode = LibraryOrganizer.preview(for: "Severance.S02E03.1080p.mkv", settings: settings)
        XCTAssertEqual(episode.kind, .tvEpisode)
        XCTAssertEqual(episode.relativePath, "Series/Severance/Season 02/Severance - S02E03.mkv")
    }

    func testLibraryOrganizerCleansMovieAndTVReleaseNames() {
        let settings = CargoSettings()

        let dune = LibraryOrganizer.preview(
            for: "Jodorowsky's Dune (2013) (1080p BDRip x265 10bit EAC3 5.1 - timesuck).mkv",
            settings: settings
        )
        XCTAssertEqual(dune.relativePath, "Movies/Jodorowsky's Dune (2013).mkv")

        let sin = LibraryOrganizer.preview(
            for: "A.Touch.Of.Sin.2013.1080p.BluRay.x264.AAC5.1-[YTS.MX].mkv",
            settings: settings
        )
        XCTAssertEqual(sin.relativePath, "Movies/A Touch Of Sin (2013).mkv")

        let episode = LibraryOrganizer.preview(
            for: "Adults.2025.S02E01.1080p.WEB.h264-ETHEL[EZTVx.to].mkv",
            settings: settings
        )
        XCTAssertEqual(
            episode.relativePath,
            "TV Shows/Adults (2025)/Season 02/Adults (2025) - S02E01.mkv"
        )

        let subtitle = LibraryOrganizer.preview(for: "Adults.S02E01.srt", settings: settings)
        XCTAssertEqual(subtitle.kind, .review)
        XCTAssertNil(subtitle.relativePath)
    }

    @MainActor
    func testOnlyVideoRemoteFilesCanBeQueued() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoMediaQueueTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.remoteFiles = [
            RemoteFile(
                id: 61,
                name: "Movie.mkv",
                type: .video,
                parentID: 0,
                sizeBytes: 4,
                createdAt: Date()
            ),
            RemoteFile(
                id: 62,
                name: "Movie.srt",
                type: .other,
                parentID: 0,
                sizeBytes: 1,
                createdAt: Date()
            ),
            RemoteFile(
                id: 63,
                name: "Movie.jpg",
                type: .image,
                parentID: 0,
                sizeBytes: 1,
                createdAt: Date()
            )
        ]
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: StubPutIOClient())
        coordinator.enqueueLocalSync(remoteFileID: 62)
        coordinator.enqueueLocalSync(remoteFileID: 63)
        XCTAssertTrue(coordinator.state.localJobs.isEmpty)

        coordinator.enqueueLocalSync(remoteFileID: 61)
        XCTAssertEqual(coordinator.state.localJobs.map(\.remoteFileID), [61])
    }

    @MainActor
    func testBackgroundCycleDownloadsAndOrganizesNewCompletedTransfer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoBackgroundTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let libraryRoot = directory.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let newFile = RemoteFile(
            id: 71,
            name: "New.Movie.2026.1080p.mkv",
            type: .video,
            parentID: 0,
            sizeBytes: 9,
            createdAt: Date()
        )
        let showsFolder = RemoteFile(
            id: 80,
            name: "Shows",
            type: .folder,
            parentID: 0,
            sizeBytes: 0,
            createdAt: Date()
        )
        let previousTransfer = RemoteTransfer(
            id: 70,
            name: "Previous.Movie.mkv",
            status: .completed,
            progress: 1,
            sizeBytes: 4,
            updatedAt: Date()
        )
        let newTransfer = RemoteTransfer(
            id: 71,
            name: newFile.name,
            status: .completed,
            progress: 1,
            sizeBytes: 4,
            updatedAt: Date()
        )

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.settings = CargoSettings(libraryRootPath: libraryRoot.path, imdbWatchlistURL: "")
        state.seenRemoteMediaFileIDs = [previousTransfer.id]
        state.remoteMediaBaselineEstablished = true
        try store.replace(with: state)

        let coordinator = CargoCoordinator(
            store: store,
            client: StubPutIOClient(
                transfers: [previousTransfer, newTransfer],
                filesByParent: [0: [showsFolder], 80: [newFile]]
            )
        )
        let summary = await coordinator.runBackgroundCycle()

        let job = try XCTUnwrap(coordinator.state.localJobs.first)
        XCTAssertEqual(job.status, .completed)
        XCTAssertTrue(job.destination?.hasSuffix("Movies/New Movie (2026).mkv") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.destination!))
        XCTAssertEqual(summary.discovered, ["Shows/New.Movie.2026.1080p.mkv"])
        XCTAssertEqual(summary.downloaded, [newFile.name])
        XCTAssertEqual(summary.organized, [newFile.name])
        XCTAssertEqual(summary.deleted, [newFile.name])
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(
            coordinator.state.history.map(\.title),
            ["Organized", "Deleted from Put.io", "Downloaded", "New Put.io media found"]
        )
    }

    func testPutIOTransferMappingNormalizesPercentAndStatus() throws {
        let data = Data(
            """
            {"transfers":[{"id":7,"name":"Episode.mkv","status":"COMPLETED","size":2048,"percent_done":100,"created_at":"2026-09-12T08:00:00Z"}]}
            """.utf8
        )
        let envelope = try JSONDecoder().decode(PutIOTransferListEnvelope.self, from: data)
        let transfer = PutIOAPIClient.mapTransfer(envelope.transfers[0])

        XCTAssertEqual(transfer.id, 7)
        XCTAssertEqual(transfer.status, .completed)
        XCTAssertEqual(transfer.progress, 1)
        XCTAssertEqual(transfer.sizeBytes, 2048)
    }

    func testPutIOFileMappingPreservesFolderAndSize() throws {
        let data = Data(
            """
            {"files":[{"id":42,"name":"Shows","file_type":"FOLDER","parent_id":0,"size":0,"created_at":"2026-09-12T08:00:00Z"},{"id":43,"name":"episode.mkv","file_type":"VIDEO","parent_id":42,"size":4096,"created_at":"2026-09-12T08:00:00Z"}]}
            """.utf8
        )
        let envelope = try JSONDecoder().decode(PutIOFileListEnvelope.self, from: data)
        let folder = PutIOAPIClient.mapFile(envelope.files[0])
        let video = PutIOAPIClient.mapFile(envelope.files[1])

        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.type, .folder)
        XCTAssertFalse(video.isFolder)
        XCTAssertEqual(video.parentID, 42)
        XCTAssertEqual(video.sizeBytes, 4096)
    }

    func testPutIOOAuthBuildsAndParsesCallback() throws {
        let authorizationURL = try PutIOOAuth.authorizationURL(state: "state-123")
        let queryItems = try XCTUnwrap(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        let query = queryItems.reduce(into: [String: String]()) { values, item in
            if let value = item.value {
                values[item.name] = value
            }
        }

        XCTAssertEqual(query["client_id"], "9732")
        XCTAssertEqual(query["response_type"], "token")
        XCTAssertEqual(query["redirect_uri"], "cargo://oauth/callback")
        XCTAssertEqual(query["state"], "state-123")

        let callbackURL = try XCTUnwrap(
            URL(string: "cargo://oauth/callback#access_token=token-abc&state=state-123")
        )
        let callback = try PutIOOAuth.parseCallback(callbackURL, expectedState: "state-123")
        XCTAssertEqual(callback.accessToken, "token-abc")
    }

    func testPutIOOAuthRejectsStateMismatch() throws {
        let callbackURL = try XCTUnwrap(
            URL(string: "cargo://oauth/callback#access_token=token-abc&state=wrong")
        )
        XCTAssertThrowsError(try PutIOOAuth.parseCallback(callbackURL, expectedState: "expected")) { error in
            XCTAssertEqual(error as? PutIOOAuth.OAuthError, .stateMismatch)
        }
    }

    @MainActor
    func testLocalSyncWritesToStagingAndNeedsReview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoSyncTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let libraryRoot = directory.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.remoteFiles = [
            RemoteFile(
                id: 55,
                name: "Movie/2026.mkv",
                type: .video,
                parentID: 0,
                sizeBytes: 9,
                createdAt: Date()
            )
        ]
        state.localJobs = []
        state.settings = CargoSettings(libraryRootPath: libraryRoot.path)
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: StubPutIOClient())
        coordinator.enqueueLocalSync(remoteFileID: 55)
        await coordinator.processLocalSync(remoteFileID: 55)

        let job = try XCTUnwrap(coordinator.state.localJobs.first)
        XCTAssertEqual(job.status, .needsReview)
        XCTAssertEqual(job.progress, 1)
        XCTAssertEqual(job.destination?.hasSuffix("_Inbox/Movie-2026.mkv"), true)
        XCTAssertEqual(
            try String(contentsOfFile: job.destination!),
            "test file"
        )
    }

    @MainActor
    func testVerifiedLocalCopyDeletesRemoteFileAndEmptyParentFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoCleanupTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let libraryRoot = directory.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let folder = RemoteFile(
            id: 80,
            name: "Movies",
            type: .folder,
            parentID: 0,
            sizeBytes: 0,
            createdAt: Date()
        )
        let file = RemoteFile(
            id: 81,
            name: "Movie.2026.mkv",
            path: "Movies/Movie.2026.mkv",
            type: .video,
            parentID: folder.id,
            sizeBytes: 9,
            createdAt: Date()
        )

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.remoteFiles = [file]
        state.remoteMediaFiles = [file]
        state.remoteFolders = [folder]
        state.settings = CargoSettings(
            libraryRootPath: libraryRoot.path,
            automaticOrganizationEnabled: false,
            automaticRemoteCleanupEnabled: true
        )
        try store.replace(with: state)

        let recorder = StubDeleteRecorder()
        let coordinator = CargoCoordinator(
            store: store,
            client: StubPutIOClient(deleteRecorder: recorder)
        )
        coordinator.enqueueLocalSync(remoteFileID: file.id)
        await coordinator.processLocalSync(remoteFileID: file.id)

        XCTAssertEqual(recorder.ids, [file.id, folder.id])
        // Cargo's own cleanup must not park files in the trash, or the quota never frees.
        XCTAssertEqual(recorder.skippedTrash, [true, true])
        XCTAssertEqual(coordinator.state.deletedRemoteFileIDs, [file.id])
        XCTAssertEqual(coordinator.state.deletedRemoteFolderIDs, [folder.id])
        XCTAssertEqual(coordinator.state.localJobs.first?.status, .needsReview)
    }

    @MainActor
    func testOrganizeLocalJobMovesInboxFileToMovies() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoOrganizeTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let libraryRoot = directory.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.remoteFiles = [
            RemoteFile(
                id: 56,
                name: "Arrival.2016.1080p.mkv",
                type: .video,
                parentID: 0,
                sizeBytes: 9,
                createdAt: Date()
            )
        ]
        state.settings = CargoSettings(libraryRootPath: libraryRoot.path)
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: StubPutIOClient())
        coordinator.enqueueLocalSync(remoteFileID: 56)
        await coordinator.processLocalSync(remoteFileID: 56)
        let jobBeforeOrganize = try XCTUnwrap(coordinator.state.localJobs.first)

        try coordinator.organizeLocalJob(jobID: jobBeforeOrganize.id)

        let job = try XCTUnwrap(coordinator.state.localJobs.first)
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.destination?.hasSuffix("Movies/Arrival (2016).mkv"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.destination!))
    }

    @MainActor
    func testInboxScanFindsAndOrganizesUntrackedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoInboxTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let libraryRoot = directory.appendingPathComponent("Library", isDirectory: true)
        let inboxURL = libraryRoot.appendingPathComponent("_Inbox", isDirectory: true)
        let nestedInboxURL = inboxURL.appendingPathComponent("Legacy", isDirectory: true)
        let sourceURL = nestedInboxURL.appendingPathComponent("Untracked.Movie.2026.mp4")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: nestedInboxURL, withIntermediateDirectories: true)
        try Data("test file".utf8).write(to: sourceURL)
        try Data().write(to: nestedInboxURL.appendingPathComponent(".DS_Store"))
        try Data().write(to: nestedInboxURL.appendingPathComponent("Untracked.Movie.2026.srt"))
        try Data().write(to: nestedInboxURL.appendingPathComponent("Untracked.Movie.2026.jpg"))
        try Data().write(to: nestedInboxURL.appendingPathComponent("Untracked.Movie.2026.nfo"))

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.settings = CargoSettings(libraryRootPath: libraryRoot.path)
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: StubPutIOClient())
        XCTAssertEqual(coordinator.inboxFileURLs().map(\.lastPathComponent), ["Untracked.Movie.2026.mp4"])

        try coordinator.organizeInboxFile(at: sourceURL)

        let destination = libraryRoot.appendingPathComponent("Movies/Untracked Movie (2026).mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedInboxURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: nestedInboxURL.appendingPathComponent("Untracked.Movie.2026.srt").path
            )
        )
    }

    @MainActor
    func testRemoteFolderNavigationTracksParent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoFolderTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CargoStore(stateURL: stateURL)
        var state = store.snapshot()
        state.remoteFiles = [
            RemoteFile(
                id: 42,
                name: "Shows",
                type: .folder,
                parentID: 0,
                sizeBytes: 0,
                createdAt: Date()
            )
        ]
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: StubPutIOClient())
        await coordinator.openRemoteFolder(remoteFolderID: 42)

        XCTAssertEqual(coordinator.remoteFolderName, "Shows")
        XCTAssertTrue(coordinator.canGoBackRemoteFolder)
        XCTAssertEqual(coordinator.state.remoteFiles.map(\.id), [56])

        await coordinator.goBackRemoteFolder()
        XCTAssertEqual(coordinator.remoteFolderName, "Put.io root")
        XCTAssertFalse(coordinator.canGoBackRemoteFolder)
    }
}

private final class StubDeleteRecorder: @unchecked Sendable {
    var ids: [Int] = []
    var skippedTrash: [Bool] = []
    var extracted: [Int] = []
    var extractions: [PutIOExtraction] = []
}

extension CargoTests {
    @MainActor
    func testBackgroundCycleAsksPutIOToExtractArchivesThenRemovesThem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CargoArchiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CargoStore(stateURL: directory.appendingPathComponent("state.json"))
        var state = store.snapshot()
        state.settings = CargoSettings(imdbWatchlistURL: "")
        try store.replace(with: state)

        let archive = RemoteFile(id: 90, name: "Release.rar", type: .archive, parentID: 0, sizeBytes: 5, createdAt: Date())
        let recorder = StubDeleteRecorder()
        let coordinator = CargoCoordinator(
            store: store,
            client: StubPutIOClient(filesByParent: [0: [archive]], deleteRecorder: recorder)
        )

        // First cycle: the archive is discovered and extraction requested.
        _ = await coordinator.runBackgroundCycle()
        XCTAssertEqual(recorder.extracted, [archive.id])
        XCTAssertEqual(coordinator.state.requestedExtractionFileIDs, [archive.id])
        XCTAssertTrue(recorder.ids.isEmpty)

        // Put.io reports it done: the archive is deleted, skipping the trash.
        recorder.extractions = [PutIOExtraction(id: 1, name: archive.name, status: .completed, message: nil)]
        _ = await coordinator.runBackgroundCycle()
        XCTAssertEqual(recorder.extracted, [archive.id], "no second extraction request")
        XCTAssertEqual(recorder.ids, [archive.id])
        XCTAssertEqual(recorder.skippedTrash, [true])
        XCTAssertTrue(coordinator.state.requestedExtractionFileIDs.isEmpty)
    }
}

private struct StubPutIOClient: PutIOClient {
    let transfers: [RemoteTransfer]
    let filesByParent: [Int: [RemoteFile]]
    let deleteRecorder: StubDeleteRecorder

    init(
        transfers: [RemoteTransfer] = [],
        filesByParent: [Int: [RemoteFile]] = [:],
        deleteRecorder: StubDeleteRecorder = StubDeleteRecorder()
    ) {
        self.transfers = transfers
        self.filesByParent = filesByParent
        self.deleteRecorder = deleteRecorder
    }

    func fetchAccount() async throws -> PutIOAccountSummary {
        PutIOAccountSummary(id: 1, username: "test")
    }

    func fetchTransfers() async throws -> [RemoteTransfer] { transfers }

    func fetchFiles(parentID: Int, types: [String]?) async throws -> [RemoteFile] {
        if let files = filesByParent[parentID] {
            return files
        }
        guard parentID == 42 else { return [] }
        return [
            RemoteFile(
                id: 56,
                name: "Episode.mkv",
                type: .video,
                parentID: 42,
                sizeBytes: 4,
                createdAt: Date()
            )
        ]
    }

    func downloadFile(fileID: Int, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test file".utf8).write(to: destinationURL)
    }

    func deleteFile(fileID: Int, skipTrash: Bool) async throws {
        deleteRecorder.ids.append(fileID)
        deleteRecorder.skippedTrash.append(skipTrash)
    }

    func extractFiles(ids: [Int]) async throws {
        deleteRecorder.extracted.append(contentsOf: ids)
    }

    func fetchExtractions() async throws -> [PutIOExtraction] { deleteRecorder.extractions }
}
