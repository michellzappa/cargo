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
    let displayName: String?
    let posterURL: String?
    let status: RemoteTransferStatus
    let statusLabel: String
    let progress: Double
    let sizeBytes: Int64
    let updatedAt: Date
    /// Why the transfer looks stuck or failed. Nil when it is fine.
    let problem: String?

    init(_ transfer: RemoteTransfer, displayName: String? = nil, posterURL: String? = nil) {
        id = transfer.id
        name = transfer.name
        self.displayName = displayName
        self.posterURL = posterURL
        status = transfer.status
        statusLabel = transfer.status.displayName
        progress = transfer.progress
        sizeBytes = transfer.sizeBytes
        updatedAt = transfer.updatedAt
        problem = transfer.problem
    }
}

struct CargoRemoteFile: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let posterURL: String?
    /// Put.io's remote path, never a local filesystem path.
    let remotePath: String
    let type: RemoteFileType
    let typeLabel: String
    let parentID: Int
    let sizeBytes: Int64
    let createdAt: Date

    init(_ file: RemoteFile, posterURL: String? = nil) {
        id = file.id
        name = file.name
        self.posterURL = posterURL
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
    let displayName: String?
    let posterURL: String?
    let status: LocalSyncStatus
    let statusLabel: String
    let progress: Double
    let hasError: Bool
    let errorMessage: String?
    let updatedAt: Date

    init(_ job: LocalSyncJob, displayName: String? = nil, posterURL: String? = nil) {
        id = job.id
        remoteFileID = job.remoteFileID
        name = job.name
        self.displayName = displayName
        self.posterURL = posterURL
        status = job.status
        statusLabel = job.status.displayName
        progress = job.progress
        hasError = job.errorMessage != nil
        errorMessage = job.errorMessage
        updatedAt = job.updatedAt
    }
}

struct CargoRemoteDiskUsage: Codable, Equatable, Sendable {
    let availableBytes: Int64
    let usedBytes: Int64
    let totalBytes: Int64

    init(_ disk: PutIODiskUsage) {
        availableBytes = disk.availableBytes
        usedBytes = disk.usedBytes
        totalBytes = disk.totalBytes
    }
}

struct CargoRemoteTitleMetadata: Codable, Equatable, Sendable {
    let tmdbID: Int
    let mediaType: String
    let posterURL: String?
    let overview: String?
    let rating: Double?
    let externalURL: String
    let episodeCounts: [Int: Int]

    init(_ metadata: TMDBMetadata) {
        tmdbID = metadata.tmdbID
        mediaType = metadata.mediaType.rawValue
        posterURL = metadata.posterURL?.absoluteString
        overview = metadata.overview
        rating = metadata.voteAverage
        externalURL = metadata.pageURL.absoluteString
        episodeCounts = metadata.episodeCounts
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
    let metadata: CargoRemoteTitleMetadata?

    init(_ item: LibraryItem, metadata: TMDBMetadata? = nil) {
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
        self.metadata = metadata.map(CargoRemoteTitleMetadata.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, year, relativePath, sizeBytes, addedAt, seasonCount, episodeCount, episodes, metadata
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
        metadata = try values.decodeIfPresent(CargoRemoteTitleMetadata.self, forKey: .metadata)
    }
}

struct CargoRemoteWatchlistItem: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let year: Int?
    let titleType: String?
    let addedAt: Date?
    let metadata: CargoRemoteTitleMetadata?

    init(_ item: IMDbWatchlistItem, metadata: TMDBMetadata? = nil) {
        id = item.id
        title = item.title
        year = item.year
        titleType = item.titleType
        addedAt = item.addedAt
        self.metadata = metadata.map(CargoRemoteTitleMetadata.init)
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
    let source: String?
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
        source = movie.source?.displayName
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

enum CargoRemoteLinkSanitizer {
    private static let sensitiveQueryNames = Set(["access_token", "download_token", "token"])
    private static let sensitiveFeedQuerySubstrings = [
        "passkey", "pass", "token", "key", "secret", "auth", "sig", "hash", "credential", "session"
    ]

    static func sanitize(_ link: String) -> String {
        guard let components = URLComponents(string: link) else { return link }
        let containsSensitiveQuery = components.queryItems?.contains { item in
            sensitiveQueryNames.contains(item.name.lowercased())
        } == true
        return containsSensitiveQuery ? "" : link
    }

    /// Strips credentials and token-like query parameters from a feed URL so
    /// passkeys never appear in snapshots, API responses, CLI or MCP output.
    static func sanitizeFeedURL(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return "" }
        components.user = nil
        components.password = nil
        if let items = components.queryItems {
            let safeItems = items.filter { !isSensitiveFeedQueryItem($0) }
            components.queryItems = safeItems.isEmpty ? nil : safeItems
        }
        return components.string ?? ""
    }

    private static func isSensitiveFeedQueryItem(_ item: URLQueryItem) -> Bool {
        let lowerName = item.name.lowercased()
        if sensitiveFeedQuerySubstrings.contains(where: { lowerName.contains($0) }) {
            return true
        }
        if let value = item.value, looksLikeToken(value) {
            return true
        }
        return false
    }

    private static func looksLikeToken(_ value: String) -> Bool {
        guard value.count >= 16 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let hasLetter = value.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasDigit = value.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        return hasLetter && hasDigit
    }
}

struct CargoRemoteSubscription: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: SubscriptionKind
    let quality: QualityProfile?
    let backfill: SubscriptionBackfillPolicy
    let paused: Bool
    let createdAt: Date
    let lastCheckedAt: Date?
    let lastError: String?

    init(_ subscription: Subscription) {
        id = subscription.id
        switch subscription.kind {
        case .series(let imdbID, let tmdbID, let title, let year):
            kind = .series(imdbID: imdbID, tmdbID: tmdbID, title: title, year: year)
        case .feed(let url, let title, let keywords, let unwantedKeywords):
            kind = .feed(
                url: CargoRemoteLinkSanitizer.sanitizeFeedURL(url),
                title: title,
                keywords: keywords,
                unwantedKeywords: unwantedKeywords
            )
        }
        quality = subscription.quality
        backfill = subscription.backfill
        paused = subscription.paused
        createdAt = subscription.createdAt
        lastCheckedAt = subscription.lastCheckedAt
        lastError = subscription.lastError
    }
}

struct CargoRemoteEpisodeLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let imdbID: String
    let season: Int
    let episode: Int
    let state: EpisodeLedgerState
    let stateLabel: String
    let subscriptionID: UUID?
    let releaseTitle: String?
    let putIOTransferID: Int?
    let airedAt: Date?
    let updatedAt: Date
    let attempts: Int
    let nextAttemptAt: Date?

    init(_ entry: EpisodeLedgerEntry) {
        id = entry.id
        imdbID = entry.imdbID
        season = entry.season
        episode = entry.episode
        state = entry.state
        stateLabel = entry.state.displayName
        subscriptionID = entry.subscriptionID
        releaseTitle = entry.releaseTitle
        putIOTransferID = entry.putIOTransferID
        airedAt = entry.airedAt
        updatedAt = entry.updatedAt
        attempts = entry.attempts
        nextAttemptAt = entry.nextAttemptAt
    }
}

struct CargoRemoteSeries: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let imdbID: String
    let title: String
    let year: Int
    let source: String?
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
        source = show.source?.displayName
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
    let appleTV: CargoRemoteConnection?
    let disk: CargoRemoteDiskUsage?
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
    /// The URL belonging to the requesting client, or the resident URL when
    /// this snapshot is produced locally.
    let watchlistURL: String?
    let subscriptions: [CargoRemoteSubscription]
    let episodeLedger: [CargoRemoteEpisodeLedgerEntry]
    let qualityProfile: QualityProfile?

    init(
        generatedAt: Date,
        lastUpdated: Date,
        putIO: CargoRemoteConnection,
        chill: CargoRemoteConnection,
        appleTV: CargoRemoteConnection?,
        disk: CargoRemoteDiskUsage?,
        remoteFolderID: Int,
        remoteFolderName: String,
        canGoBackRemoteFolder: Bool,
        transfers: [CargoRemoteTransfer],
        files: [CargoRemoteFile],
        mediaFiles: [CargoRemoteFile],
        syncJobs: [CargoRemoteSyncJob],
        library: [CargoRemoteLibraryItem],
        watchlist: [CargoRemoteWatchlistItem],
        history: [CargoRemoteHistoryEntry],
        chillSearch: CargoRemoteSearchState,
        chillCatalog: CargoRemoteCatalogState,
        watchlistStatus: String,
        watchlistURL: String?,
        subscriptions: [CargoRemoteSubscription] = [],
        episodeLedger: [CargoRemoteEpisodeLedgerEntry] = [],
        qualityProfile: QualityProfile? = nil
    ) {
        self.generatedAt = generatedAt
        self.lastUpdated = lastUpdated
        self.putIO = putIO
        self.chill = chill
        self.appleTV = appleTV
        self.disk = disk
        self.remoteFolderID = remoteFolderID
        self.remoteFolderName = remoteFolderName
        self.canGoBackRemoteFolder = canGoBackRemoteFolder
        self.transfers = transfers
        self.files = files
        self.mediaFiles = mediaFiles
        self.syncJobs = syncJobs
        self.library = library
        self.watchlist = watchlist
        self.history = history
        self.chillSearch = chillSearch
        self.chillCatalog = chillCatalog
        self.watchlistStatus = watchlistStatus
        self.watchlistURL = watchlistURL
        self.subscriptions = subscriptions
        self.episodeLedger = episodeLedger
        self.qualityProfile = qualityProfile
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, lastUpdated, putIO, chill, appleTV, disk
        case remoteFolderID, remoteFolderName, canGoBackRemoteFolder
        case transfers, files, mediaFiles, syncJobs, library, watchlist, history
        case chillSearch, chillCatalog, watchlistStatus, watchlistURL
        case subscriptions, episodeLedger, qualityProfile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        putIO = try c.decode(CargoRemoteConnection.self, forKey: .putIO)
        chill = try c.decode(CargoRemoteConnection.self, forKey: .chill)
        appleTV = try c.decodeIfPresent(CargoRemoteConnection.self, forKey: .appleTV)
        disk = try c.decodeIfPresent(CargoRemoteDiskUsage.self, forKey: .disk)
        remoteFolderID = try c.decode(Int.self, forKey: .remoteFolderID)
        remoteFolderName = try c.decode(String.self, forKey: .remoteFolderName)
        canGoBackRemoteFolder = try c.decode(Bool.self, forKey: .canGoBackRemoteFolder)
        transfers = try c.decode([CargoRemoteTransfer].self, forKey: .transfers)
        files = try c.decode([CargoRemoteFile].self, forKey: .files)
        mediaFiles = try c.decode([CargoRemoteFile].self, forKey: .mediaFiles)
        syncJobs = try c.decode([CargoRemoteSyncJob].self, forKey: .syncJobs)
        library = try c.decode([CargoRemoteLibraryItem].self, forKey: .library)
        watchlist = try c.decode([CargoRemoteWatchlistItem].self, forKey: .watchlist)
        history = try c.decode([CargoRemoteHistoryEntry].self, forKey: .history)
        chillSearch = try c.decode(CargoRemoteSearchState.self, forKey: .chillSearch)
        chillCatalog = try c.decode(CargoRemoteCatalogState.self, forKey: .chillCatalog)
        watchlistStatus = try c.decode(String.self, forKey: .watchlistStatus)
        watchlistURL = try c.decodeIfPresent(String.self, forKey: .watchlistURL)
        subscriptions = try c.decodeIfPresent([CargoRemoteSubscription].self, forKey: .subscriptions) ?? []
        episodeLedger = try c.decodeIfPresent([CargoRemoteEpisodeLedgerEntry].self, forKey: .episodeLedger) ?? []
        qualityProfile = try c.decodeIfPresent(QualityProfile.self, forKey: .qualityProfile)
    }
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
                posterURL: $0.posterURL,
                status: $0.status,
                progress: $0.progress,
                sizeBytes: $0.sizeBytes,
                updatedAt: $0.updatedAt,
                problem: $0.problem
            )
        }
        state.remoteFiles = files.map {
            RemoteFile(
                id: $0.id,
                name: $0.name,
                path: $0.remotePath,
                posterURL: $0.posterURL,
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
                posterURL: $0.posterURL,
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
                name: $0.displayName ?? $0.name,
                status: $0.status,
                progress: $0.progress,
                destination: nil,
                errorMessage: $0.hasError ? "Remote job failed" : nil,
                posterURL: $0.posterURL,
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
        state.subscriptions = subscriptions.map {
            Subscription(
                id: $0.id,
                kind: $0.kind,
                quality: $0.quality,
                backfill: $0.backfill,
                paused: $0.paused,
                createdAt: $0.createdAt,
                lastCheckedAt: $0.lastCheckedAt,
                lastError: $0.lastError
            )
        }
        state.episodeLedger = episodeLedger.map {
            EpisodeLedgerEntry(
                imdbID: $0.imdbID,
                season: $0.season,
                episode: $0.episode,
                state: $0.state,
                subscriptionID: $0.subscriptionID,
                releaseTitle: $0.releaseTitle,
                putIOTransferID: $0.putIOTransferID,
                airedAt: $0.airedAt,
                updatedAt: $0.updatedAt,
                attempts: $0.attempts,
                nextAttemptAt: $0.nextAttemptAt
            )
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
    case refreshPersonalWatchlist(url: String?)
    case clearFailedJobs
    case clearHistory
    case playLibraryItem(id: String)
    case playLibraryEpisode(id: String, season: Int, episode: Int)
    case addSeriesSubscription(imdbID: String, tmdbID: Int, title: String, year: Int?, backfill: SubscriptionBackfillPolicy?)
    case addFeedSubscription(url: String, title: String, keywords: [String], unwantedKeywords: [String], backfill: SubscriptionBackfillPolicy?)
    case removeSubscription(id: UUID)
    case setSubscriptionPaused(id: UUID, paused: Bool)
    case setEpisodeLedgerState(imdbID: String, season: Int, episode: Int, state: EpisodeLedgerState)

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case id
        case url
        case title
        case remoteFileID
        case season
        case episode
        case imdbID
        case tmdbID
        case year
        case keywords
        case unwantedKeywords
        case backfill
        case paused
        case state
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
        case refreshPersonalWatchlist
        case clearFailedJobs
        case clearHistory
        case playLibraryItem
        case playLibraryEpisode
        case addSeriesSubscription
        case addFeedSubscription
        case removeSubscription
        case setSubscriptionPaused
        case setEpisodeLedgerState
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
        case .refreshPersonalWatchlist:
            self = .refreshPersonalWatchlist(url: try values.decodeIfPresent(String.self, forKey: .url))
        case .clearFailedJobs:
            self = .clearFailedJobs
        case .clearHistory:
            self = .clearHistory
        case .playLibraryItem:
            self = .playLibraryItem(id: try values.decode(String.self, forKey: .id))
        case .playLibraryEpisode:
            self = .playLibraryEpisode(
                id: try values.decode(String.self, forKey: .id),
                season: try values.decode(Int.self, forKey: .season),
                episode: try values.decode(Int.self, forKey: .episode)
            )
        case .addSeriesSubscription:
            self = .addSeriesSubscription(
                imdbID: try values.decode(String.self, forKey: .imdbID),
                tmdbID: try values.decode(Int.self, forKey: .tmdbID),
                title: try values.decode(String.self, forKey: .title),
                year: try values.decodeIfPresent(Int.self, forKey: .year),
                backfill: try values.decodeIfPresent(SubscriptionBackfillPolicy.self, forKey: .backfill)
            )
        case .addFeedSubscription:
            self = .addFeedSubscription(
                url: try values.decode(String.self, forKey: .url),
                title: try values.decode(String.self, forKey: .title),
                keywords: try values.decodeIfPresent([String].self, forKey: .keywords) ?? [],
                unwantedKeywords: try values.decodeIfPresent([String].self, forKey: .unwantedKeywords) ?? [],
                backfill: try values.decodeIfPresent(SubscriptionBackfillPolicy.self, forKey: .backfill)
            )
        case .removeSubscription:
            self = .removeSubscription(id: try values.decode(UUID.self, forKey: .id))
        case .setSubscriptionPaused:
            self = .setSubscriptionPaused(
                id: try values.decode(UUID.self, forKey: .id),
                paused: try values.decode(Bool.self, forKey: .paused)
            )
        case .setEpisodeLedgerState:
            self = .setEpisodeLedgerState(
                imdbID: try values.decode(String.self, forKey: .imdbID),
                season: try values.decode(Int.self, forKey: .season),
                episode: try values.decode(Int.self, forKey: .episode),
                state: try values.decode(EpisodeLedgerState.self, forKey: .state)
            )
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
        case .refreshPersonalWatchlist(let url):
            try values.encode(Kind.refreshPersonalWatchlist, forKey: .type)
            try values.encodeIfPresent(url, forKey: .url)
        case .clearFailedJobs:
            try values.encode(Kind.clearFailedJobs, forKey: .type)
        case .clearHistory:
            try values.encode(Kind.clearHistory, forKey: .type)
        case .playLibraryItem(let id):
            try values.encode(Kind.playLibraryItem, forKey: .type)
            try values.encode(id, forKey: .id)
        case .playLibraryEpisode(let id, let season, let episode):
            try values.encode(Kind.playLibraryEpisode, forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(season, forKey: .season)
            try values.encode(episode, forKey: .episode)
        case .addSeriesSubscription(let imdbID, let tmdbID, let title, let year, let backfill):
            try values.encode(Kind.addSeriesSubscription, forKey: .type)
            try values.encode(imdbID, forKey: .imdbID)
            try values.encode(tmdbID, forKey: .tmdbID)
            try values.encode(title, forKey: .title)
            try values.encodeIfPresent(year, forKey: .year)
            try values.encodeIfPresent(backfill, forKey: .backfill)
        case .addFeedSubscription(let url, let title, let keywords, let unwantedKeywords, let backfill):
            try values.encode(Kind.addFeedSubscription, forKey: .type)
            try values.encode(url, forKey: .url)
            try values.encode(title, forKey: .title)
            try values.encode(keywords, forKey: .keywords)
            try values.encode(unwantedKeywords, forKey: .unwantedKeywords)
            try values.encodeIfPresent(backfill, forKey: .backfill)
        case .removeSubscription(let id):
            try values.encode(Kind.removeSubscription, forKey: .type)
            try values.encode(id, forKey: .id)
        case .setSubscriptionPaused(let id, let paused):
            try values.encode(Kind.setSubscriptionPaused, forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(paused, forKey: .paused)
        case .setEpisodeLedgerState(let imdbID, let season, let episode, let state):
            try values.encode(Kind.setEpisodeLedgerState, forKey: .type)
            try values.encode(imdbID, forKey: .imdbID)
            try values.encode(season, forKey: .season)
            try values.encode(episode, forKey: .episode)
            try values.encode(state, forKey: .state)
        }
    }
}

enum CargoRemoteControlError: LocalizedError, Equatable, Sendable {
    case targetNotFound(String)
    case appleTVUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .targetNotFound(let target):
            "Cargo could not find \(target). Refresh and try again."
        case .appleTVUnavailable(let status):
            "Apple TV playback is unavailable: \(status)"
        }
    }
}

@MainActor
protocol CargoRemoteControlling: AnyObject {
    func snapshot(clientID: UUID?) -> CargoRemoteSnapshot
    func search(query: String) async throws -> CargoRemoteSearchState
    func execute(_ command: CargoRemoteCommand, clientID: UUID?) async throws -> CargoRemoteSnapshot
}

/// The single application-facing boundary for future resident API transports.
@MainActor
final class CargoRemoteController: CargoRemoteControlling {
    private let coordinator: CargoCoordinator

    init(coordinator: CargoCoordinator) {
        self.coordinator = coordinator
    }

    func snapshot(clientID: UUID? = nil) -> CargoRemoteSnapshot {
        // Remote clients need the resident to restore its saved Apple TV
        // session even when the Mac Settings page has not been opened.
        coordinator.appleTVPlayback.start()
        let state = coordinator.state
        let clientWatchlist = clientID.map { coordinator.clientWatchlist(for: $0) ?? CargoClientWatchlist() }
        let watchlistItems = clientWatchlist?.items ?? state.imdbWatchlistItems
        return CargoRemoteSnapshot(
            generatedAt: Date(),
            lastUpdated: state.lastUpdated,
            putIO: CargoRemoteConnection(connected: coordinator.isConnected, status: coordinator.putIOStatus),
            chill: CargoRemoteConnection(connected: coordinator.isChillConnected, status: coordinator.chillStatus),
            appleTV: CargoRemoteConnection(connected: coordinator.appleTVPlayback.isConnected, status: coordinator.appleTVPlayback.statusText),
            disk: coordinator.diskUsage.map(CargoRemoteDiskUsage.init),
            remoteFolderID: coordinator.remoteFolderID,
            remoteFolderName: coordinator.remoteFolderName,
            canGoBackRemoteFolder: coordinator.canGoBackRemoteFolder,
            transfers: state.transfers.map { transfer in
                let presentation = mediaPresentation(for: transfer.name, state: state)
                return CargoRemoteTransfer(
                    transfer,
                    displayName: presentation.displayName,
                    posterURL: presentation.posterURL
                )
            },
            files: state.remoteFiles.map { file in
                CargoRemoteFile(file, posterURL: mediaPresentation(for: file.name, state: state).posterURL)
            },
            mediaFiles: state.remoteMediaFiles.map { file in
                CargoRemoteFile(file, posterURL: mediaPresentation(for: file.name, state: state).posterURL)
            },
            syncJobs: state.localJobs.map { job in
                let presentation = mediaPresentation(for: job.name, state: state)
                return CargoRemoteSyncJob(
                    job,
                    displayName: presentation.displayName,
                    posterURL: presentation.posterURL
                )
            },
            library: state.libraryItems.map { CargoRemoteLibraryItem($0, metadata: state.metadata[$0.id]) },
            watchlist: watchlistItems.map { CargoRemoteWatchlistItem($0, metadata: state.metadata[$0.id]) },
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
            watchlistStatus: clientWatchlist?.status ?? coordinator.imdbWatchlistStatus,
            watchlistURL: clientWatchlist?.url ?? state.settings.imdbWatchlistURL,
            subscriptions: state.subscriptions.map(CargoRemoteSubscription.init),
            episodeLedger: state.episodeLedger.map(CargoRemoteEpisodeLedgerEntry.init),
            qualityProfile: state.settings.qualityProfile
        )
    }

    private func mediaPresentation(for name: String, state: CargoState) -> (displayName: String, posterURL: String?) {
        (
            LibraryOrganizer.displayTitle(for: name),
            LibraryOrganizer.posterURL(for: name, library: state.libraryItems, metadata: state.metadata)?.absoluteString
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

    func execute(_ command: CargoRemoteCommand, clientID: UUID? = nil) async throws -> CargoRemoteSnapshot {
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
        case .refreshPersonalWatchlist(let url):
            guard let clientID else {
                throw CargoRemoteControlError.targetNotFound("connected Cargo client")
            }
            _ = await coordinator.refreshClientWatchlist(for: clientID, requestedURL: url)
        case .clearFailedJobs:
            coordinator.clearFailedJobs()
        case .clearHistory:
            coordinator.clearHistory()
        case .playLibraryItem(let id):
            guard let metadata = coordinator.state.metadata[id] else {
                throw CargoRemoteControlError.targetNotFound("library metadata for \(id)")
            }
            guard coordinator.state.libraryItems.contains(where: { $0.id == id && $0.kind == .movie }) else {
                throw CargoRemoteControlError.targetNotFound("library item \(id)")
            }
            switch coordinator.appleTVPlayback.play(metadata: metadata) {
            case .sent:
                break
            case .needsSetup:
                throw CargoRemoteControlError.appleTVUnavailable(coordinator.appleTVPlayback.statusText)
            }
        case .playLibraryEpisode(let id, let season, let episode):
            guard let metadata = coordinator.state.metadata[id], metadata.mediaType == .tv else {
                throw CargoRemoteControlError.targetNotFound("TV metadata for \(id)")
            }
            guard let item = coordinator.state.libraryItems.first(where: { $0.id == id && $0.kind == .show }) else {
                throw CargoRemoteControlError.targetNotFound("TV library item \(id)")
            }
            guard item.episodes[season, default: []].contains(episode) else {
                let label = String(format: "S%02dE%02d", season, episode)
                throw CargoRemoteControlError.targetNotFound("episode \(label)")
            }
            switch coordinator.appleTVPlayback.play(metadata: metadata, season: season, episode: episode) {
            case .sent:
                break
            case .needsSetup:
                throw CargoRemoteControlError.appleTVUnavailable(coordinator.appleTVPlayback.statusText)
            }
        case .addSeriesSubscription(let imdbID, let tmdbID, let title, let year, let backfill):
            try coordinator.addSeriesSubscription(
                imdbID: imdbID,
                tmdbID: tmdbID,
                title: title,
                year: year,
                backfill: backfill ?? .newOnly
            )
        case .addFeedSubscription(let url, let title, let keywords, let unwantedKeywords, let backfill):
            try coordinator.addFeedSubscription(
                url: url,
                title: title,
                keywords: keywords,
                unwantedKeywords: unwantedKeywords,
                backfill: backfill ?? .newOnly
            )
        case .removeSubscription(let id):
            do {
                try coordinator.removeSubscription(id: id)
            } catch SubscriptionError.subscriptionNotFound {
                throw CargoRemoteControlError.targetNotFound("subscription \(id.uuidString.lowercased())")
            }
        case .setSubscriptionPaused(let id, let paused):
            do {
                try coordinator.setSubscriptionPaused(id: id, paused: paused)
            } catch SubscriptionError.subscriptionNotFound {
                throw CargoRemoteControlError.targetNotFound("subscription \(id.uuidString.lowercased())")
            }
        case .setEpisodeLedgerState(let imdbID, let season, let episode, let state):
            try coordinator.setEpisodeLedgerState(
                imdbID: imdbID,
                season: season,
                episode: episode,
                state: state
            )
        }
        return snapshot(clientID: clientID)
    }
}
