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
        XCTAssertEqual(store.snapshot().transfers.count, 2)

        try store.save()

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
}

private struct StubPutIOClient: PutIOClient {
    func fetchAccount() async throws -> PutIOAccountSummary {
        PutIOAccountSummary(id: 1, username: "test")
    }

    func fetchTransfers() async throws -> [RemoteTransfer] { [] }

    func fetchFiles(parentID: Int) async throws -> [RemoteFile] { [] }

    func downloadFile(fileID: Int, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test file".utf8).write(to: destinationURL)
    }
}
