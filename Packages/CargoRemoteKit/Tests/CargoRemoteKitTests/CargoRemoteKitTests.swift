import XCTest
@testable import CargoRemoteKit

final class CargoRemoteKitTests: XCTestCase {
    func testCommandsUseResidentWireFormat() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let commands: [CargoRemoteCommand] = [
            .refresh,
            .addTransfer(url: "magnet:?xt=urn:btih:test"),
            .cancelTransfer(id: 42),
            .enqueueLocalSync(remoteFileID: 99),
            .openRemoteFolder(remoteFolderID: 12),
            .goBackRemoteFolder
        ]

        for command in commands {
            let data = try encoder.encode(command)
            XCTAssertEqual(try decoder.decode(CargoRemoteCommand.self, from: data), command)
        }
    }

    func testPairingLinkRoundTripsPlusCharacters() {
        let link = CargoPairingLink(serverURL: "http://cargo.tailnet.ts.net:39817", token: "ab+c/d=e")
        XCTAssertEqual(CargoPairingLink(parsing: link.urlString), link)
        XCTAssertNil(CargoPairingLink(parsing: "http://cargo.tailnet.ts.net:39817"))
    }

    func testResidentSnapshotFixtureDecodes() throws {
        let json = #"""
        {
          "generatedAt":"2026-09-21T20:00:00Z",
          "lastUpdated":"2026-09-21T19:59:00Z",
          "putIO":{"connected":true,"status":"Connected as test"},
          "chill":{"connected":false,"status":"Not configured"},
          "remoteFolderID":0,
          "remoteFolderName":"Put.io root",
          "canGoBackRemoteFolder":false,
          "transfers":[{"id":1,"name":"Arrival.mkv","status":"downloading","statusLabel":"Downloading","progress":0.5,"sizeBytes":100,"updatedAt":"2026-09-21T19:58:00Z"}],
          "files":[],
          "mediaFiles":[],
          "syncJobs":[],
          "library":[],
          "watchlist":[],
          "history":[],
          "chillSearch":{"query":"","status":"Search Chill for a release","results":[]},
          "chillCatalog":{"status":"Top movies and series appear here","movies":[],"series":[]},
          "watchlistStatus":"Not synced yet"
        }
        """#.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CargoRemoteSnapshot.self, from: json)
        XCTAssertEqual(snapshot.transfers.first?.name, "Arrival.mkv")
        XCTAssertEqual(snapshot.transfers.first?.status, .downloading)
        XCTAssertTrue(snapshot.putIO.connected)
    }
}
