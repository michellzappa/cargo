import Foundation

/// A deliberately small, Codable view of Cargo's local state.
///
/// This is the contract a future HTTP/WebSocket transport will expose. It is
/// intentionally not a Codable wrapper around CargoState: CargoState contains
/// security-scoped bookmarks, local paths, and settings that must stay on the
/// resident Mac.
struct CargoRemoteConnection: Codable, Equatable, Sendable {
    let connected: Bool
    let status: String
}

struct CargoRemoteTransfer: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let status: RemoteTransferStatus
    let statusLabel: String
    let progress: Double
    let sizeBytes: Int64
    let updatedAt: Date

    init(_ transfer: RemoteTransfer) {
        id = transfer.id
        name = transfer.name
        status = transfer.status
        statusLabel = transfer.status.displayName
        progress = transfer.progress
        sizeBytes = transfer.sizeBytes
        updatedAt = transfer.updatedAt
    }
}

struct CargoRemoteFile: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    /// Put.io's remote path, never a local filesystem path.
    let remotePath: String
    let type: RemoteFileType
    let typeLabel: String
    let parentID: Int
    let sizeBytes: Int64
    let createdAt: Date

    init(_ file: RemoteFile) {
        id = file.id
        name = file.name
        remotePath = file.displayPath
        type = file.type
        typeLabel = file.type.displayName
        parentID = file.parentID
        sizeBytes = file.sizeBytes
        createdAt = file.createdAt
    }
}

struct CargoRemoteSyncJob: Codable, Equatable, Sendable {
    let id: UUID
    let remoteFileID: Int
    let name: String
    let status: LocalSyncStatus
    let statusLabel: String
    let progress: Double
    let hasError: Bool
    let updatedAt: Date

    init(_ job: LocalSyncJob) {
        id = job.id
        remoteFileID = job.remoteFileID
        name = job.name
        status = job.status
        statusLabel = job.status.displayName
        progress = job.progress
        hasError = job.errorMessage != nil
        updatedAt = job.updatedAt
    }
}

struct CargoRemoteLibraryItem: Codable, Equatable, Sendable {
    let id: String
    let kind: LibraryItem.Kind
    let title: String
    let year: Int?
    /// Relative to the configured library root; never an absolute path.
    let relativePath: String
    let sizeBytes: Int64
    let addedAt: Date
    let seasonCount: Int
    let episodeCount: Int

    init(_ item: LibraryItem) {
        id = item.id
        kind = item.kind
        title = item.title
        year = item.year
        relativePath = item.relativePath
        sizeBytes = item.sizeBytes
        addedAt = item.addedAt
        seasonCount = item.seasonCount
        episodeCount = item.episodeCount
    }
}

struct CargoRemoteWatchlistItem: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let year: Int?
    let titleType: String?
    let addedAt: Date?

    init(_ item: IMDbWatchlistItem) {
        id = item.id
        title = item.title
        year = item.year
        titleType = item.titleType
        addedAt = item.addedAt
    }
}

struct CargoRemoteHistoryEntry: Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let kind: CargoHistoryKind
    let title: String
    let detail: String

    init(_ entry: CargoHistoryEntry) {
        id = entry.id
        date = entry.date
        kind = entry.kind
        title = entry.title
        detail = entry.detail
    }
}

struct CargoRemoteReleaseInfo: Codable, Equatable, Sendable {
    let title: String
    let year: Int?
    let season: Int?
    let episode: Int?
    let episodeEnd: Int?
    let resolution: String
    let quality: String
    let source: String
    let codec: String
    let hdr: String
    let audio: String
    let group: String
    let container: String
    let language: String
    let region: String
    let size: String
    let bitDepth: String
    let edition: String
    let complete: Bool

    init(_ info: ChillReleaseInfo) {
        title = info.title
        year = info.year
        season = info.season
        episode = info.episode
        episodeEnd = info.episodeEnd
        resolution = info.resolution
        quality = info.quality
        source = info.source
        codec = info.codec
        hdr = info.hdr
        audio = info.audio
        group = info.group
        container = info.container
        language = info.language
        region = info.region
        size = info.size
        bitDepth = info.bitDepth
        edition = info.edition
        complete = info.complete
    }
}

struct CargoRemoteSearchResult: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let indexer: String
    let link: String
    let imdbID: String?
    let peers: Int64
    let seeders: Int64
    let size: Int64
    let source: String
    let uploadedAt: String
    let releaseInfo: CargoRemoteReleaseInfo?

    init(_ result: ChillSearchResult) {
        id = result.id
        title = result.title
        indexer = result.indexer
        link = result.link
        imdbID = result.imdbID
        peers = result.peers
        seeders = result.seeders
        size = result.size
        source = result.source
        uploadedAt = result.uploadedAt
        releaseInfo = result.releaseInfo.map(CargoRemoteReleaseInfo.init)
    }
}

struct CargoRemoteMovie: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let year: Int
    let displayTitle: String
    let link: String
    let peers: Int64
    let seeders: Int64
    let size: Int64
    let uploadedAt: String
    let posterURL: String
    let rating: Double
    let externalURL: String
    let overview: String
    let genres: [String]

    init(_ movie: ChillMovie) {
        id = movie.id
        title = movie.title
        year = movie.year
        displayTitle = movie.displayTitle
        link = movie.link
        peers = movie.peers
        seeders = movie.seeders
        size = movie.size
        uploadedAt = movie.uploadedAt
        posterURL = movie.posterURL
        rating = movie.rating
        externalURL = movie.externalURL
        overview = movie.overview
        genres = movie.genres
    }
}

struct CargoRemoteSeries: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let imdbID: String
    let title: String
    let year: Int
    let posterURL: String
    let rating: Double
    let overview: String
    let externalURL: String
    let seasonCount: Int
    let status: Int
    let statusLabel: String
    let networks: [String]

    init(_ show: ChillTVShow) {
        id = show.id
        imdbID = show.imdbID
        title = show.title
        year = show.year
        posterURL = show.posterURL
        rating = show.rating
        overview = show.overview
        externalURL = show.externalURL
        seasonCount = show.seasonCount
        status = show.status
        statusLabel = show.statusLabel
        networks = show.networks
    }
}

struct CargoRemoteSearchState: Codable, Equatable, Sendable {
    let query: String
    let status: String
    let results: [CargoRemoteSearchResult]
}

struct CargoRemoteCatalogState: Codable, Equatable, Sendable {
    let status: String
    let movies: [CargoRemoteMovie]
    let series: [CargoRemoteSeries]
}

struct CargoRemoteSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let lastUpdated: Date
    let putIO: CargoRemoteConnection
    let chill: CargoRemoteConnection
    let remoteFolderID: Int
    let remoteFolderName: String
    let canGoBackRemoteFolder: Bool
    let transfers: [CargoRemoteTransfer]
    let files: [CargoRemoteFile]
    let mediaFiles: [CargoRemoteFile]
    let syncJobs: [CargoRemoteSyncJob]
    let library: [CargoRemoteLibraryItem]
    let watchlist: [CargoRemoteWatchlistItem]
    let history: [CargoRemoteHistoryEntry]
    let chillSearch: CargoRemoteSearchState
    let chillCatalog: CargoRemoteCatalogState
    let watchlistStatus: String
}

/// Commands are transport-neutral. An HTTP adapter can decode this enum
/// without knowing anything about AppKit, Keychain, or CargoCoordinator.
enum CargoRemoteCommand: Codable, Equatable, Sendable {
    case refresh
    case refreshChillCatalog
    case searchChill(query: String)
    case sendChillResult(id: String)
    case sendChillMovie(id: String)
    case addTransfer(url: String)
    case cancelTransfer(id: Int)
    case retryTransfer(id: Int)
    case enqueueLocalSync(remoteFileID: Int)
    case organizeLocalJob(id: UUID)
    case refreshWatchlist

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case id
        case url
        case remoteFileID
    }

    private enum Kind: String, Codable {
        case refresh
        case refreshChillCatalog
        case searchChill
        case sendChillResult
        case sendChillMovie
        case addTransfer
        case cancelTransfer
        case retryTransfer
        case enqueueLocalSync
        case organizeLocalJob
        case refreshWatchlist
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .refresh:
            self = .refresh
        case .refreshChillCatalog:
            self = .refreshChillCatalog
        case .searchChill:
            self = .searchChill(query: try values.decode(String.self, forKey: .query))
        case .sendChillResult:
            self = .sendChillResult(id: try values.decode(String.self, forKey: .id))
        case .sendChillMovie:
            self = .sendChillMovie(id: try values.decode(String.self, forKey: .id))
        case .addTransfer:
            self = .addTransfer(url: try values.decode(String.self, forKey: .url))
        case .cancelTransfer:
            self = .cancelTransfer(id: try values.decode(Int.self, forKey: .id))
        case .retryTransfer:
            self = .retryTransfer(id: try values.decode(Int.self, forKey: .id))
        case .enqueueLocalSync:
            self = .enqueueLocalSync(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .organizeLocalJob:
            self = .organizeLocalJob(id: try values.decode(UUID.self, forKey: .id))
        case .refreshWatchlist:
            self = .refreshWatchlist
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .refresh:
            try values.encode(Kind.refresh, forKey: .type)
        case .refreshChillCatalog:
            try values.encode(Kind.refreshChillCatalog, forKey: .type)
        case .searchChill(let query):
            try values.encode(Kind.searchChill, forKey: .type)
            try values.encode(query, forKey: .query)
        case .sendChillResult(let id):
            try values.encode(Kind.sendChillResult, forKey: .type)
            try values.encode(id, forKey: .id)
        case .sendChillMovie(let id):
            try values.encode(Kind.sendChillMovie, forKey: .type)
            try values.encode(id, forKey: .id)
        case .addTransfer(let url):
            try values.encode(Kind.addTransfer, forKey: .type)
            try values.encode(url, forKey: .url)
        case .cancelTransfer(let id):
            try values.encode(Kind.cancelTransfer, forKey: .type)
            try values.encode(id, forKey: .id)
        case .retryTransfer(let id):
            try values.encode(Kind.retryTransfer, forKey: .type)
            try values.encode(id, forKey: .id)
        case .enqueueLocalSync(let remoteFileID):
            try values.encode(Kind.enqueueLocalSync, forKey: .type)
            try values.encode(remoteFileID, forKey: .remoteFileID)
        case .organizeLocalJob(let id):
            try values.encode(Kind.organizeLocalJob, forKey: .type)
            try values.encode(id, forKey: .id)
        case .refreshWatchlist:
            try values.encode(Kind.refreshWatchlist, forKey: .type)
        }
    }
}

enum CargoRemoteControlError: LocalizedError, Equatable, Sendable {
    case targetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .targetNotFound(let target):
            "Cargo could not find \(target). Refresh and try again."
        }
    }
}

@MainActor
protocol CargoRemoteControlling: AnyObject {
    func snapshot() -> CargoRemoteSnapshot
    func execute(_ command: CargoRemoteCommand) async throws -> CargoRemoteSnapshot
}

/// The single application-facing boundary for future resident API transports.
@MainActor
final class CargoRemoteController: CargoRemoteControlling {
    private let coordinator: CargoCoordinator

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
    }

    func snapshot() -> CargoRemoteSnapshot {
        let state = coordinator.state
        return CargoRemoteSnapshot(
            generatedAt: Date(),
            lastUpdated: state.lastUpdated,
            putIO: CargoRemoteConnection(connected: coordinator.isConnected, status: coordinator.putIOStatus),
            chill: CargoRemoteConnection(connected: coordinator.isChillConnected, status: coordinator.chillStatus),
            remoteFolderID: coordinator.remoteFolderID,
            remoteFolderName: coordinator.remoteFolderName,
            canGoBackRemoteFolder: coordinator.canGoBackRemoteFolder,
            transfers: state.transfers.map(CargoRemoteTransfer.init),
            files: state.remoteFiles.map(CargoRemoteFile.init),
            mediaFiles: state.remoteMediaFiles.map(CargoRemoteFile.init),
            syncJobs: state.localJobs.map(CargoRemoteSyncJob.init),
            library: state.libraryItems.map(CargoRemoteLibraryItem.init),
            watchlist: state.imdbWatchlistItems.map(CargoRemoteWatchlistItem.init),
            history: state.history.map(CargoRemoteHistoryEntry.init),
            chillSearch: CargoRemoteSearchState(
                query: coordinator.chillSearchQuery,
                status: coordinator.chillSearchStatus,
                results: coordinator.chillSearchResults.map(CargoRemoteSearchResult.init)
            ),
            chillCatalog: CargoRemoteCatalogState(
                status: coordinator.chillCatalogStatus,
                movies: coordinator.chillCatalogMovies.map(CargoRemoteMovie.init),
                series: coordinator.chillCatalogShows.map(CargoRemoteSeries.init)
            ),
            watchlistStatus: coordinator.imdbWatchlistStatus
        )
    }

    func execute(_ command: CargoRemoteCommand) async throws -> CargoRemoteSnapshot {
        switch command {
        case .refresh:
            await coordinator.refreshFromPutIO(force: true)
        case .refreshChillCatalog:
            await coordinator.refreshChillCatalog()
        case .searchChill(let query):
            await coordinator.searchChill(query: query)
        case .sendChillResult(let id):
            guard let result = coordinator.chillSearchResults.first(where: { $0.id == id }) else {
                throw CargoRemoteControlError.targetNotFound("Chill release \(id)")
            }
            try await coordinator.sendChillResult(result)
        case .sendChillMovie(let id):
            guard let movie = coordinator.chillCatalogMovies.first(where: { $0.id == id }) else {
                throw CargoRemoteControlError.targetNotFound("Chill movie \(id)")
            }
            try await coordinator.sendChillMovie(movie)
        case .addTransfer(let url):
            try await coordinator.addTransfer(url: url)
        case .cancelTransfer(let id):
            try await coordinator.cancelTransfer(id: id)
        case .retryTransfer(let id):
            try await coordinator.retryTransfer(id: id)
        case .enqueueLocalSync(let remoteFileID):
            coordinator.enqueueLocalSync(remoteFileID: remoteFileID)
        case .organizeLocalJob(let id):
            _ = try coordinator.organizeLocalJob(jobID: id)
        case .refreshWatchlist:
            _ = await coordinator.refreshIMDbWatchlist(force: true)
        }
        return snapshot()
    }
}
