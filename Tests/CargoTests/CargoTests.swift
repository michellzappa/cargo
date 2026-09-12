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
        try store.replace(with: state)

        XCTAssertEqual(store.snapshot().transfers.count, 2)

        let reloaded = CargoStore(stateURL: stateURL)
        XCTAssertEqual(reloaded.snapshot().transfers.map(\.id), [1001, 1002])
        XCTAssertEqual(reloaded.snapshot().remoteFiles.count, 2)
        XCTAssertEqual(reloaded.snapshot().localJobs.count, 1)
    }

    func testStatusesHaveHumanReadableNames() {
        XCTAssertEqual(RemoteTransferStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(LocalSyncStatus.needsReview.displayName, "Needs review")
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
        XCTAssertEqual(job.destination?.hasSuffix(".cargo-incoming/Movie-2026.mkv"), true)
        XCTAssertEqual(
            try String(contentsOfFile: job.destination!),
            "test file"
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
    func fetchAccount() async throws -> PutIOAccountSummary {
        PutIOAccountSummary(id: 1, username: "test")
    }

    func fetchTransfers() async throws -> [RemoteTransfer] { [] }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] {
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
