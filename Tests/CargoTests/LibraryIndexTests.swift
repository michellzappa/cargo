import Foundation
import XCTest
@testable import Cargo

final class LibraryIndexTests: XCTestCase {
    func testScanReadsMoviesAndShowsFromTheOrganizerLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryIndexTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Movies/Arrival (2016).mkv",
            "Movies/Nested/Dune (2021).mp4",
            "Movies/poster.jpg",
            "TV Shows/Adults (2025)/Season 01/Adults (2025) - S01E01.mkv",
            "TV Shows/Adults (2025)/Season 01/Adults (2025) - S01E02.mkv",
            "TV Shows/Adults (2025)/Season 02/Adults (2025) - S02E01.mkv",
            "TV Shows/Empty Show/notes.txt"
        ]
        for path in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }

        let items = LibraryIndex.scan(root: root, settings: CargoSettings())

        XCTAssertEqual(items.map(\.id), ["show:Adults (2025)", "movie:Arrival (2016)", "movie:Dune (2021)"])
        let show = try XCTUnwrap(items.first { $0.kind == .show })
        XCTAssertEqual(show.title, "Adults")
        XCTAssertEqual(show.year, 2025)
        XCTAssertEqual(show.episodes, [1: [1, 2], 2: [1]])
        XCTAssertEqual(show.episodeCount, 3)
        XCTAssertEqual(show.sizeBytes, 3)
        let movie = try XCTUnwrap(items.first { $0.id == "movie:Arrival (2016)" })
        XCTAssertEqual(movie.relativePath, "Movies/Arrival (2016).mkv")
    }

    func testTitleParsing() {
        XCTAssertEqual(LibraryIndex.titleAndYear(from: "Arrival (2016)").0, "Arrival")
        XCTAssertEqual(LibraryIndex.titleAndYear(from: "Arrival (2016)").1, 2016)
        XCTAssertEqual(LibraryIndex.titleAndYear(from: "No Year").1, nil)
        XCTAssertEqual(LibraryIndex.seasonEpisode(from: "Show (2020) - S03E12.mkv")?.0, 3)
        XCTAssertEqual(LibraryIndex.seasonEpisode(from: "Show (2020) - S03E12.mkv")?.1, 12)
        XCTAssertNil(LibraryIndex.seasonEpisode(from: "Movie.mkv"))
    }
}

final class TMDBNormalizeTests: XCTestCase {
    func testNormalizeIgnoresPunctuationCaseAndAccents() {
        XCTAssertEqual(TMDBClient.normalize("Titan: The OceanGate Disaster"), "titan the oceangate disaster")
        XCTAssertEqual(TMDBClient.normalize("The Man from U.N.C.L.E."), "the man from u n c l e")
        XCTAssertEqual(TMDBClient.normalize("Amélie & Co"), "amelie and co")
    }
}

final class InterruptedJobTests: XCTestCase {
    @MainActor
    func testDownloadingJobsAreRequeuedOnLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CargoRequeue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CargoStore(stateURL: directory.appendingPathComponent("state.json"))
        var state = store.snapshot()
        state.localJobs = [
            LocalSyncJob(id: UUID(), remoteFileID: 1, name: "stuck.mkv", status: .downloading, progress: 0.4, destination: nil, errorMessage: nil, updatedAt: .distantPast),
            LocalSyncJob(id: UUID(), remoteFileID: 2, name: "done.mkv", status: .completed, progress: 1, destination: nil, errorMessage: nil, updatedAt: .distantPast)
        ]
        try store.replace(with: state)

        let coordinator = CargoCoordinator(store: store, client: UnconfiguredPutIOClient())

        XCTAssertEqual(coordinator.state.localJobs.map(\.status), [.queued, .completed])
        XCTAssertEqual(coordinator.state.localJobs[0].progress, 0)
        XCTAssertEqual(coordinator.state.history.first?.title, "Resuming interrupted download")
    }
}
