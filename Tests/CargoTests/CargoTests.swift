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
        XCTAssertEqual(reloaded.snapshot().localJobs.count, 1)
    }

    func testStatusesHaveHumanReadableNames() {
        XCTAssertEqual(RemoteTransferStatus.downloading.displayName, "Downloading")
        XCTAssertEqual(LocalSyncStatus.needsReview.displayName, "Needs review")
    }
}
