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

/// The identity a Cargo installation presents when it connects to another
/// Cargo installation. Credentials stay out of this model; authentication is
/// handled by the resident API bearer token.
struct CargoRemotePresenceRegistration: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let platform: String
}

struct CargoRemotePresenceHeartbeat: Codable, Equatable, Sendable {
    let id: UUID
}

struct CargoRemotePeer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let platform: String
    let connectedAt: Date
    let lastSeenAt: Date
}

struct CargoRemotePresence: Codable, Equatable, Sendable {
    let residentName: String
    let revision: UInt64
    let generatedAt: Date
    let clients: [CargoRemotePeer]
}

/// Deliberately unauthenticated, low-information response used only to find
/// Cargo peers before the user has entered the resident bearer token.
struct CargoRemoteDiscovery: Codable, Equatable, Sendable {
    let service: String
    let apiVersion: String
    let instanceID: UUID
    let name: String
    let port: Int
}

/// In-memory presence for the resident process. A client must heartbeat before
/// the lease expires; this avoids claiming that a laptop is connected forever
/// after sleep, termination, or a network change.
@MainActor
final class CargoRemotePresenceRegistry {
    static let didChange = Notification.Name("CargoRemotePresenceRegistry.didChange")

    let residentID: UUID
    private struct Entry {
        var peer: CargoRemotePeer
    }

    private let residentName: String
    private let leaseDuration: TimeInterval
    private var entries: [UUID: Entry] = [:]
    private(set) var revision: UInt64 = 0

    init(
        residentID: UUID = UUID(),
        residentName: String = Host.current().localizedName ?? "Cargo",
        leaseDuration: TimeInterval = 45
    ) {
        self.residentID = residentID
        self.residentName = residentName
        self.leaseDuration = leaseDuration
    }

    func register(_ registration: CargoRemotePresenceRegistration, now: Date = Date()) -> CargoRemotePresence {
        let connectedAt = entries[registration.id]?.peer.connectedAt ?? now
        entries[registration.id] = Entry(peer: CargoRemotePeer(
            id: registration.id,
            name: registration.name,
            platform: registration.platform,
            connectedAt: connectedAt,
            lastSeenAt: now
        ))
        revision &+= 1
        notifyChange()
        return snapshot(now: now)
    }

    func heartbeat(_ heartbeat: CargoRemotePresenceHeartbeat, now: Date = Date()) -> CargoRemotePresence? {
        pruneExpired(now: now)
        guard var entry = entries[heartbeat.id] else { return nil }
        entry.peer = CargoRemotePeer(
            id: entry.peer.id,
            name: entry.peer.name,
            platform: entry.peer.platform,
            connectedAt: entry.peer.connectedAt,
            lastSeenAt: now
        )
        entries[heartbeat.id] = entry
        revision &+= 1
        notifyChange()
        return snapshot(now: now)
    }

    func unregister(_ heartbeat: CargoRemotePresenceHeartbeat, now: Date = Date()) -> CargoRemotePresence? {
        pruneExpired(now: now)
        guard entries.removeValue(forKey: heartbeat.id) != nil else { return nil }
        revision &+= 1
        notifyChange()
        return snapshot(now: now)
    }

    func snapshot(now: Date = Date()) -> CargoRemotePresence {
        pruneExpired(now: now)
        return CargoRemotePresence(
            residentName: residentName,
            revision: revision,
            generatedAt: now,
            clients: entries.values.map(\.peer).sorted { $0.connectedAt < $1.connectedAt }
        )
    }

    private func pruneExpired(now: Date) {
        let expired = entries.filter { now.timeIntervalSince($0.value.peer.lastSeenAt) > leaseDuration }.map(\.key)
        guard !expired.isEmpty else { return }
        for id in expired { entries.removeValue(forKey: id) }
        revision &+= 1
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
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
    let episodes: [Int: [Int]]

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
        episodes = item.episodes
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, year, relativePath, sizeBytes, addedAt, seasonCount, episodeCount, episodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(LibraryItem.Kind.self, forKey: .kind)
        title = try values.decode(String.self, forKey: .title)
        year = try values.decodeIfPresent(Int.self, forKey: .year)
        relativePath = try values.decode(String.self, forKey: .relativePath)
        sizeBytes = try values.decode(Int64.self, forKey: .sizeBytes)
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        seasonCount = try values.decodeIfPresent(Int.self, forKey: .seasonCount) ?? 0
        episodeCount = try values.decodeIfPresent(Int.self, forKey: .episodeCount) ?? 0
        episodes = try values.decodeIfPresent([Int: [Int]].self, forKey: .episodes) ?? [:]
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
        link = CargoRemoteLinkSanitizer.sanitize(result.link)
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
        link = CargoRemoteLinkSanitizer.sanitize(movie.link)
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

private enum CargoRemoteLinkSanitizer {
    private static let sensitiveQueryNames = Set(["access_token", "download_token", "token"])

    static func sanitize(_ link: String) -> String {
        guard let components = URLComponents(string: link) else { return link }
        let containsSensitiveQuery = components.queryItems?.contains { item in
            sensitiveQueryNames.contains(item.name.lowercased())
        } == true
        return containsSensitiveQuery ? "" : link
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

extension CargoRemoteSnapshot {
    /// Rehydrates the remote-safe projection into the local display models.
    /// Local settings are deliberately supplied by the client; credentials,
    /// bookmarks, and absolute paths never cross the remote boundary.
    func dashboardState(preserving base: CargoState) -> CargoState {
        var state = base
        state.transfers = transfers.map {
            RemoteTransfer(
                id: $0.id,
                name: $0.name,
                status: $0.status,
                progress: $0.progress,
                sizeBytes: $0.sizeBytes,
                updatedAt: $0.updatedAt
            )
        }
        state.remoteFiles = files.map {
            RemoteFile(
                id: $0.id,
                name: $0.name,
                path: $0.remotePath,
                type: $0.type,
                parentID: $0.parentID,
                sizeBytes: $0.sizeBytes,
                createdAt: $0.createdAt
            )
        }
        state.remoteMediaFiles = mediaFiles.map {
            RemoteFile(
                id: $0.id,
                name: $0.name,
                path: $0.remotePath,
                type: $0.type,
                parentID: $0.parentID,
                sizeBytes: $0.sizeBytes,
                createdAt: $0.createdAt
            )
        }
        state.remoteFolders = state.remoteFiles.filter(\.isFolder)
        state.remoteArchiveFiles = state.remoteFiles.filter(\.isArchive)
        state.localJobs = syncJobs.map {
            LocalSyncJob(
                id: $0.id,
                remoteFileID: $0.remoteFileID,
                name: $0.name,
                status: $0.status,
                progress: $0.progress,
                destination: nil,
                errorMessage: $0.hasError ? "Remote job failed" : nil,
                updatedAt: $0.updatedAt
            )
        }
        state.libraryItems = library.map {
            LibraryItem(
                id: $0.id,
                kind: $0.kind,
                title: $0.title,
                year: $0.year,
                relativePath: $0.relativePath,
                sizeBytes: $0.sizeBytes,
                addedAt: $0.addedAt,
                episodes: $0.episodes
            )
        }
        state.imdbWatchlistItems = watchlist.map {
            IMDbWatchlistItem(id: $0.id, title: $0.title, year: $0.year, titleType: $0.titleType, addedAt: $0.addedAt)
        }
        state.history = history.map {
            CargoHistoryEntry(id: $0.id, date: $0.date, kind: $0.kind, title: $0.title, detail: $0.detail)
        }
        state.lastUpdated = lastUpdated
        return state
    }
}

extension ChillReleaseInfo {
    init(_ remote: CargoRemoteReleaseInfo) {
        title = remote.title
        year = remote.year
        season = remote.season
        episode = remote.episode
        episodeEnd = remote.episodeEnd
        resolution = remote.resolution
        quality = remote.quality
        source = remote.source
        codec = remote.codec
        hdr = remote.hdr
        audio = remote.audio
        group = remote.group
        container = remote.container
        language = remote.language
        region = remote.region
        size = remote.size
        bitDepth = remote.bitDepth
        edition = remote.edition
        complete = remote.complete
    }
}

extension ChillSearchResult {
    init(_ remote: CargoRemoteSearchResult) {
        id = remote.id
        title = remote.title
        indexer = remote.indexer
        link = remote.link
        imdbID = remote.imdbID
        peers = remote.peers
        seeders = remote.seeders
        size = remote.size
        source = remote.source
        uploadedAt = remote.uploadedAt
        releaseInfo = remote.releaseInfo.map(ChillReleaseInfo.init)
    }
}

extension ChillMovie {
    init(_ remote: CargoRemoteMovie) {
        id = remote.id
        title = remote.title
        year = remote.year
        source = nil
        titlePretty = remote.displayTitle
        link = remote.link
        peers = remote.peers
        seeders = remote.seeders
        size = remote.size
        uploadedAt = remote.uploadedAt
        posterURL = remote.posterURL
        rating = remote.rating
        externalURL = remote.externalURL
        overview = remote.overview
        genres = remote.genres
    }
}

extension ChillTVShow {
    init(_ remote: CargoRemoteSeries) {
        imdbID = remote.imdbID
        title = remote.title
        year = remote.year
        source = nil
        posterURL = remote.posterURL
        rating = remote.rating
        overview = remote.overview
        externalURL = remote.externalURL
        seasonCount = remote.seasonCount
        status = remote.status
        networks = remote.networks
    }
}

/// Commands are transport-neutral. An HTTP adapter can decode this enum
/// without knowing anything about AppKit, Keychain, or CargoCoordinator.
enum CargoRemoteCommand: Codable, Equatable, Sendable {
    case refresh
    case refreshChillCatalog
    case searchChill(query: String)
    case sendChillResult(id: String)
    /// A release the client found through its own per-client search; the
    /// resident never held it, so the link travels with the command.
    case sendChillRelease(url: String, title: String?)
    case sendChillMovie(id: String)
    case addTransfer(url: String)
    case cancelTransfer(id: Int)
    case retryTransfer(id: Int)
    case cleanFinishedTransfers
    case requestExtraction(remoteFileID: Int)
    case openRemoteFolder(remoteFolderID: Int)
    case goBackRemoteFolder
    case deleteRemoteFile(remoteFileID: Int)
    case enqueueLocalSync(remoteFileID: Int)
    case organizeLocalJob(id: UUID)
    case refreshWatchlist
    case clearFailedJobs
    case clearHistory

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case id
        case url
        case title
        case remoteFileID
    }

    private enum Kind: String, Codable {
        case refresh
        case refreshChillCatalog
        case searchChill
        case sendChillResult
        case sendChillRelease
        case sendChillMovie
        case addTransfer
        case cancelTransfer
        case retryTransfer
        case cleanFinishedTransfers
        case requestExtraction
        case openRemoteFolder
        case goBackRemoteFolder
        case deleteRemoteFile
        case enqueueLocalSync
        case organizeLocalJob
        case refreshWatchlist
        case clearFailedJobs
        case clearHistory
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
        case .sendChillRelease:
            self = .sendChillRelease(
                url: try values.decode(String.self, forKey: .url),
                title: try values.decodeIfPresent(String.self, forKey: .title)
            )
        case .sendChillMovie:
            self = .sendChillMovie(id: try values.decode(String.self, forKey: .id))
        case .addTransfer:
            self = .addTransfer(url: try values.decode(String.self, forKey: .url))
        case .cancelTransfer:
            self = .cancelTransfer(id: try values.decode(Int.self, forKey: .id))
        case .retryTransfer:
            self = .retryTransfer(id: try values.decode(Int.self, forKey: .id))
        case .cleanFinishedTransfers:
            self = .cleanFinishedTransfers
        case .requestExtraction:
            self = .requestExtraction(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .openRemoteFolder:
            self = .openRemoteFolder(remoteFolderID: try values.decode(Int.self, forKey: .remoteFileID))
        case .goBackRemoteFolder:
            self = .goBackRemoteFolder
        case .deleteRemoteFile:
            self = .deleteRemoteFile(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .enqueueLocalSync:
            self = .enqueueLocalSync(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .organizeLocalJob:
            self = .organizeLocalJob(id: try values.decode(UUID.self, forKey: .id))
        case .refreshWatchlist:
            self = .refreshWatchlist
        case .clearFailedJobs:
            self = .clearFailedJobs
        case .clearHistory:
            self = .clearHistory
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
        case .sendChillRelease(let url, let title):
            try values.encode(Kind.sendChillRelease, forKey: .type)
            try values.encode(url, forKey: .url)
            try values.encodeIfPresent(title, forKey: .title)
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
        case .cleanFinishedTransfers:
            try values.encode(Kind.cleanFinishedTransfers, forKey: .type)
        case .requestExtraction(let remoteFileID):
            try values.encode(Kind.requestExtraction, forKey: .type)
            try values.encode(remoteFileID, forKey: .remoteFileID)
        case .openRemoteFolder(let remoteFolderID):
            try values.encode(Kind.openRemoteFolder, forKey: .type)
            try values.encode(remoteFolderID, forKey: .remoteFileID)
        case .goBackRemoteFolder:
            try values.encode(Kind.goBackRemoteFolder, forKey: .type)
        case .deleteRemoteFile(let remoteFileID):
            try values.encode(Kind.deleteRemoteFile, forKey: .type)
            try values.encode(remoteFileID, forKey: .remoteFileID)
        case .enqueueLocalSync(let remoteFileID):
            try values.encode(Kind.enqueueLocalSync, forKey: .type)
            try values.encode(remoteFileID, forKey: .remoteFileID)
        case .organizeLocalJob(let id):
            try values.encode(Kind.organizeLocalJob, forKey: .type)
            try values.encode(id, forKey: .id)
        case .refreshWatchlist:
            try values.encode(Kind.refreshWatchlist, forKey: .type)
        case .clearFailedJobs:
            try values.encode(Kind.clearFailedJobs, forKey: .type)
        case .clearHistory:
            try values.encode(Kind.clearHistory, forKey: .type)
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
    func search(query: String) async throws -> CargoRemoteSearchState
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

    /// Per-client search: runs against Chill and returns the results without
    /// touching the resident's own Discover page.
    func search(query: String) async throws -> CargoRemoteSearchState {
        let results = try await coordinator.chillReleases(matching: query)
        return CargoRemoteSearchState(
            query: query,
            status: "\(results.count) result\(results.count == 1 ? "" : "s")",
            results: results.map(CargoRemoteSearchResult.init)
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
        case .sendChillRelease(let url, let title):
            try await coordinator.sendChillRelease(url: url, title: title)
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
        case .cleanFinishedTransfers:
            try await coordinator.cleanFinishedTransfers()
        case .requestExtraction(let remoteFileID):
            try await coordinator.requestExtraction(remoteFileID: remoteFileID)
        case .openRemoteFolder(let remoteFolderID):
            await coordinator.openRemoteFolder(remoteFolderID: remoteFolderID)
        case .goBackRemoteFolder:
            await coordinator.goBackRemoteFolder()
        case .deleteRemoteFile(let remoteFileID):
            try await coordinator.deleteRemoteFile(remoteFileID: remoteFileID)
        case .enqueueLocalSync(let remoteFileID):
            coordinator.enqueueLocalSync(remoteFileID: remoteFileID)
            // Queue the resident-side work and return immediately. Downloads
            // can outlive a phone request; progress is delivered by the
            // revisioned snapshot feed instead of holding an HTTP request open.
            Task { @MainActor in
                await coordinator.processLocalSync(remoteFileID: remoteFileID)
            }
        case .organizeLocalJob(let id):
            _ = try coordinator.organizeLocalJob(jobID: id)
        case .refreshWatchlist:
            _ = await coordinator.refreshIMDbWatchlist(force: true)
        case .clearFailedJobs:
            coordinator.clearFailedJobs()
        case .clearHistory:
            coordinator.clearHistory()
        }
        return snapshot()
    }
}
