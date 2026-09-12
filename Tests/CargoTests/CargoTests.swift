import Foundation
import XCTest
@testable import Cargo

final class CargoTests: XCTestCase {
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
        XCTAssertEqual(reloaded.snapshot().seenRemoteMediaFileIDs, [2001])
        XCTAssertTrue(reloaded.snapshot().remoteMediaBaselineEstablished)
        XCTAssertFalse(reloaded.snapshot().settings.automaticSyncEnabled)
        XCTAssertTrue(reloaded.snapshot().settings.automaticOrganizationEnabled)
        XCTAssertFalse(reloaded.snapshot().settings.notificationsEnabled)
        XCTAssertFalse(reloaded.snapshot().settings.launchAtLoginEnabled)
    }

    func testStatusesHaveHumanReadableNames() {
        XCTAssertEqual(RemoteTransferStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(LocalSyncStatus.needsReview.displayName, "In inbox · awaiting organization")
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
            sizeBytes: 4,
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
        state.settings = CargoSettings(libraryRootPath: libraryRoot.path)
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
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(
            coordinator.state.history.map(\.title),
            ["Organized", "Downloaded", "New Put.io media found"]
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
                sizeBytes: 4,
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
                sizeBytes: 4,
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedInboxURL.path))
        XCTAssertTrue(
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

private struct StubPutIOClient: PutIOClient {
    let transfers: [RemoteTransfer]
    let filesByParent: [Int: [RemoteFile]]

    init(
        transfers: [RemoteTransfer] = [],
        filesByParent: [Int: [RemoteFile]] = [:]
    ) {
        self.transfers = transfers
        self.filesByParent = filesByParent
    }

    func fetchAccount() async throws -> PutIOAccountSummary {
        PutIOAccountSummary(id: 1, username: "test")
    }

    func fetchTransfers() async throws -> [RemoteTransfer] { transfers }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] {
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
}
