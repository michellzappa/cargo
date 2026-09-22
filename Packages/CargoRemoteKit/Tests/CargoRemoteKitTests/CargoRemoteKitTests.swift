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
        XCTAssertNil(snapshot.disk)
    }

    func testSnapshotCarriesDiskUsageAndDetailedSyncErrors() throws {
        let json = #"""
        {
          "generatedAt":"2026-09-21T20:00:00Z",
          "lastUpdated":"2026-09-21T19:59:00Z",
          "putIO":{"connected":true,"status":"Connected as test"},
          "chill":{"connected":false,"status":"Not configured"},
          "disk":{"availableBytes":67000000000,"usedBytes":33000000000,"totalBytes":100000000000},
          "remoteFolderID":0,
          "remoteFolderName":"Put.io root",
          "canGoBackRemoteFolder":false,
          "transfers":[],
          "files":[],
          "mediaFiles":[],
          "syncJobs":[{"id":"00000000-0000-0000-0000-000000000001","remoteFileID":7,"name":"Movie.mkv","status":"failed","statusLabel":"Failed","progress":0,"hasError":true,"errorMessage":"Saved SSD access bookmark could not be resolved.","updatedAt":"2026-09-21T19:58:00Z"}],
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
        XCTAssertEqual(snapshot.disk?.availableBytes, 67_000_000_000)
        XCTAssertEqual(snapshot.syncJobs.first?.errorMessage, "Saved SSD access bookmark could not be resolved.")
    }

    func testTitleMetadataIsOptionalAndDecodesForBrowseSurfaces() throws {
        let json = #"""
        {
          "id":"movie:Arrival (2016)",
          "kind":"movie",
          "title":"Arrival",
          "year":2016,
          "relativePath":"Movies/Arrival (2016).mkv",
          "sizeBytes":100,
          "addedAt":"2026-09-21T19:59:00Z",
          "seasonCount":0,
          "episodeCount":0,
          "episodes":{},
          "metadata":{
            "tmdbID":329865,
            "mediaType":"movie",
            "posterURL":"https://image.tmdb.org/t/p/w185/poster.jpg",
            "overview":"A linguist works to communicate with visitors.",
            "rating":7.9,
            "externalURL":"https://www.themoviedb.org/movie/329865",
            "episodeCounts":{}
          }
        }
        """#.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(CargoRemoteLibraryItem.self, from: json)
        XCTAssertEqual(item.metadata?.posterURL, "https://image.tmdb.org/t/p/w185/poster.jpg")
        XCTAssertEqual(item.metadata?.rating, 7.9)

        let legacy = #"""
        {
          "id":"movie:Old",
          "kind":"movie",
          "title":"Old",
          "year":null,
          "relativePath":"Movies/Old.mkv",
          "sizeBytes":100,
          "addedAt":"2026-09-21T19:59:00Z",
          "seasonCount":0,
          "episodeCount":0,
          "episodes":{}
        }
        """#.data(using: .utf8)!
        XCTAssertNil(try decoder.decode(CargoRemoteLibraryItem.self, from: legacy).metadata)
    }
}
