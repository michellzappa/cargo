import Foundation

// MARK: - Wire enums

public enum CargoRemoteTransferStatus: String, Codable, Sendable {
    case waiting
    case downloading
    case seeding
    case completed
    case failed
    case cancelled
    case unknown

    public var displayName: String {
        switch self {
        case .waiting: "Waiting"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}

public enum CargoRemoteLocalSyncStatus: String, Codable, Sendable {
    case queued
    case downloading
    case importing
    case completed
    case needsReview
    case failed

    public var displayName: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .importing: "Importing"
        case .completed: "Completed"
        case .needsReview: "In inbox · awaiting organization"
        case .failed: "Failed"
        }
    }
}

public enum CargoRemoteFileType: String, Codable, Sendable {
    case folder
    case video
    case audio
    case image
    case pdf
    case archive
    case other
    case unknown

    public var displayName: String {
        switch self {
        case .folder: "Folder"
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        case .archive: "Archive"
        case .pdf: "PDF"
        case .other: "File"
        case .unknown: "Unknown"
        }
    }
}

public enum CargoRemoteLibraryKind: String, Codable, Sendable {
    case movie
    case show
}

public enum CargoRemoteHistoryKind: String, Codable, Sendable {
    case info
    case success
    case warning
    case failure
}

// MARK: - Presence and discovery

public struct CargoRemoteConnection: Codable, Equatable, Sendable {
    public let connected: Bool
    public let status: String

    public init(connected: Bool, status: String) {
        self.connected = connected
        self.status = status
    }
}

public struct CargoRemotePresenceRegistration: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let platform: String

    public init(id: UUID, name: String, platform: String) {
        self.id = id
        self.name = name
        self.platform = platform
    }
}

public struct CargoRemotePresenceHeartbeat: Codable, Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct CargoRemotePeer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let platform: String
    public let connectedAt: Date
    public let lastSeenAt: Date

    public init(id: UUID, name: String, platform: String, connectedAt: Date, lastSeenAt: Date) {
        self.id = id
        self.name = name
        self.platform = platform
        self.connectedAt = connectedAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct CargoRemotePresence: Codable, Equatable, Sendable {
    public let residentName: String
    public let revision: UInt64
    public let generatedAt: Date
    public let clients: [CargoRemotePeer]

    public init(residentName: String, revision: UInt64, generatedAt: Date, clients: [CargoRemotePeer]) {
        self.residentName = residentName
        self.revision = revision
        self.generatedAt = generatedAt
        self.clients = clients
    }
}

public struct CargoRemoteDiscovery: Codable, Equatable, Sendable {
    public let service: String
    public let apiVersion: String
    public let instanceID: UUID
    public let name: String
    public let port: Int

    public init(service: String, apiVersion: String, instanceID: UUID, name: String, port: Int) {
        self.service = service
        self.apiVersion = apiVersion
        self.instanceID = instanceID
        self.name = name
        self.port = port
    }
}

// MARK: - Snapshot

public struct CargoRemoteTransfer: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let status: CargoRemoteTransferStatus
    public let statusLabel: String
    public let progress: Double
    public let sizeBytes: Int64
    public let updatedAt: Date

    public init(id: Int, name: String, status: CargoRemoteTransferStatus, statusLabel: String, progress: Double, sizeBytes: Int64, updatedAt: Date) {
        self.id = id
        self.name = name
        self.status = status
        self.statusLabel = statusLabel
        self.progress = progress
        self.sizeBytes = sizeBytes
        self.updatedAt = updatedAt
    }
}

public struct CargoRemoteFile: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let remotePath: String
    public let type: CargoRemoteFileType
    public let typeLabel: String
    public let parentID: Int
    public let sizeBytes: Int64
    public let createdAt: Date

    public init(id: Int, name: String, remotePath: String, type: CargoRemoteFileType, typeLabel: String, parentID: Int, sizeBytes: Int64, createdAt: Date) {
        self.id = id
        self.name = name
        self.remotePath = remotePath
        self.type = type
        self.typeLabel = typeLabel
        self.parentID = parentID
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}

public struct CargoRemoteSyncJob: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let remoteFileID: Int
    public let name: String
    public let status: CargoRemoteLocalSyncStatus
    public let statusLabel: String
    public let progress: Double
    public let hasError: Bool
    public let updatedAt: Date

    public init(id: UUID, remoteFileID: Int, name: String, status: CargoRemoteLocalSyncStatus, statusLabel: String, progress: Double, hasError: Bool, updatedAt: Date) {
        self.id = id
        self.remoteFileID = remoteFileID
        self.name = name
        self.status = status
        self.statusLabel = statusLabel
        self.progress = progress
        self.hasError = hasError
        self.updatedAt = updatedAt
    }
}

public struct CargoRemoteLibraryItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: CargoRemoteLibraryKind
    public let title: String
    public let year: Int?
    public let relativePath: String
    public let sizeBytes: Int64
    public let addedAt: Date
    public let seasonCount: Int
    public let episodeCount: Int
    public let episodes: [Int: [Int]]

    public init(id: String, kind: CargoRemoteLibraryKind, title: String, year: Int?, relativePath: String, sizeBytes: Int64, addedAt: Date, seasonCount: Int, episodeCount: Int, episodes: [Int: [Int]]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.episodes = episodes
    }
}

public struct CargoRemoteWatchlistItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let year: Int?
    public let titleType: String?
    public let addedAt: Date?

    public init(id: String, title: String, year: Int?, titleType: String?, addedAt: Date?) {
        self.id = id
        self.title = title
        self.year = year
        self.titleType = titleType
        self.addedAt = addedAt
    }
}

public struct CargoRemoteHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let kind: CargoRemoteHistoryKind
    public let title: String
    public let detail: String

    public init(id: UUID, date: Date, kind: CargoRemoteHistoryKind, title: String, detail: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct CargoRemoteReleaseInfo: Codable, Equatable, Sendable {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let episodeEnd: Int?
    public let resolution: String
    public let quality: String
    public let source: String
    public let codec: String
    public let hdr: String
    public let audio: String
    public let group: String
    public let container: String
    public let language: String
    public let region: String
    public let size: String
    public let bitDepth: String
    public let edition: String
    public let complete: Bool
}

public struct CargoRemoteSearchResult: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let indexer: String
    public let link: String
    public let imdbID: String?
    public let peers: Int64
    public let seeders: Int64
    public let size: Int64
    public let source: String
    public let uploadedAt: String
    public let releaseInfo: CargoRemoteReleaseInfo?
}

public struct CargoRemoteMovie: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let year: Int
    public let displayTitle: String
    public let link: String
    public let peers: Int64
    public let seeders: Int64
    public let size: Int64
    public let uploadedAt: String
    public let posterURL: String
    public let rating: Double
    public let externalURL: String
    public let overview: String
    public let genres: [String]
}

public struct CargoRemoteSeries: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let imdbID: String
    public let title: String
    public let year: Int
    public let posterURL: String
    public let rating: Double
    public let overview: String
    public let externalURL: String
    public let seasonCount: Int
    public let status: Int
    public let statusLabel: String
    public let networks: [String]
}

public struct CargoRemoteSearchState: Codable, Equatable, Sendable {
    public let query: String
    public let status: String
    public let results: [CargoRemoteSearchResult]

    public init(query: String, status: String, results: [CargoRemoteSearchResult]) {
        self.query = query
        self.status = status
        self.results = results
    }
}

public struct CargoRemoteCatalogState: Codable, Equatable, Sendable {
    public let status: String
    public let movies: [CargoRemoteMovie]
    public let series: [CargoRemoteSeries]
}

public struct CargoRemoteSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let lastUpdated: Date
    public let putIO: CargoRemoteConnection
    public let chill: CargoRemoteConnection
    public let remoteFolderID: Int
    public let remoteFolderName: String
    public let canGoBackRemoteFolder: Bool
    public let transfers: [CargoRemoteTransfer]
    public let files: [CargoRemoteFile]
    public let mediaFiles: [CargoRemoteFile]
    public let syncJobs: [CargoRemoteSyncJob]
    public let library: [CargoRemoteLibraryItem]
    public let watchlist: [CargoRemoteWatchlistItem]
    public let history: [CargoRemoteHistoryEntry]
    public let chillSearch: CargoRemoteSearchState
    public let chillCatalog: CargoRemoteCatalogState
    public let watchlistStatus: String
}

public struct CargoRemoteEvent: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let changed: Bool
    public let snapshot: CargoRemoteSnapshot?

    public init(revision: UInt64, changed: Bool, snapshot: CargoRemoteSnapshot?) {
        self.revision = revision
        self.changed = changed
        self.snapshot = snapshot
    }
}

// MARK: - API envelope and commands

public struct CargoAPIError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CargoAPIEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let ok: Bool
    public let requestID: String
    public let data: Payload?
    public let error: CargoAPIError?

    public init(ok: Bool, requestID: String, data: Payload?, error: CargoAPIError?) {
        self.ok = ok
        self.requestID = requestID
        self.data = data
        self.error = error
    }
}

public struct CargoAPIHealth: Codable, Equatable, Sendable {
    public let status: String
    public let apiVersion: String
    public let generatedAt: Date
    public var appVersion: String?

    public init(status: String, apiVersion: String, generatedAt: Date, appVersion: String? = nil) {
        self.status = status
        self.apiVersion = apiVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
    }
}

public struct CargoAPISearchRequest: Codable, Equatable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

public enum CargoRemoteCommand: Codable, Equatable, Sendable {
    case refresh
    case refreshChillCatalog
    case searchChill(query: String)
    case sendChillResult(id: String)
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

    private enum CodingKeys: String, CodingKey { case type, query, id, url, title, remoteFileID }
    private enum Kind: String, Codable {
        case refresh, refreshChillCatalog, searchChill, sendChillResult, sendChillRelease, sendChillMovie
        case addTransfer, cancelTransfer, retryTransfer, cleanFinishedTransfers, requestExtraction
        case openRemoteFolder, goBackRemoteFolder, deleteRemoteFile, enqueueLocalSync, organizeLocalJob, refreshWatchlist, clearFailedJobs, clearHistory
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .refresh: self = .refresh
        case .refreshChillCatalog: self = .refreshChillCatalog
        case .searchChill: self = .searchChill(query: try values.decode(String.self, forKey: .query))
        case .sendChillResult: self = .sendChillResult(id: try values.decode(String.self, forKey: .id))
        case .sendChillRelease: self = .sendChillRelease(url: try values.decode(String.self, forKey: .url), title: try values.decodeIfPresent(String.self, forKey: .title))
        case .sendChillMovie: self = .sendChillMovie(id: try values.decode(String.self, forKey: .id))
        case .addTransfer: self = .addTransfer(url: try values.decode(String.self, forKey: .url))
        case .cancelTransfer: self = .cancelTransfer(id: try values.decode(Int.self, forKey: .id))
        case .retryTransfer: self = .retryTransfer(id: try values.decode(Int.self, forKey: .id))
        case .cleanFinishedTransfers: self = .cleanFinishedTransfers
        case .requestExtraction: self = .requestExtraction(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .openRemoteFolder: self = .openRemoteFolder(remoteFolderID: try values.decode(Int.self, forKey: .remoteFileID))
        case .goBackRemoteFolder: self = .goBackRemoteFolder
        case .deleteRemoteFile: self = .deleteRemoteFile(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .enqueueLocalSync: self = .enqueueLocalSync(remoteFileID: try values.decode(Int.self, forKey: .remoteFileID))
        case .organizeLocalJob: self = .organizeLocalJob(id: try values.decode(UUID.self, forKey: .id))
        case .refreshWatchlist: self = .refreshWatchlist
        case .clearFailedJobs: self = .clearFailedJobs
        case .clearHistory: self = .clearHistory
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        func type(_ kind: Kind) throws { try values.encode(kind, forKey: .type) }
        switch self {
        case .refresh: try type(.refresh)
        case .refreshChillCatalog: try type(.refreshChillCatalog)
        case .searchChill(let query): try type(.searchChill); try values.encode(query, forKey: .query)
        case .sendChillResult(let id): try type(.sendChillResult); try values.encode(id, forKey: .id)
        case .sendChillRelease(let url, let title): try type(.sendChillRelease); try values.encode(url, forKey: .url); try values.encodeIfPresent(title, forKey: .title)
        case .sendChillMovie(let id): try type(.sendChillMovie); try values.encode(id, forKey: .id)
        case .addTransfer(let url): try type(.addTransfer); try values.encode(url, forKey: .url)
        case .cancelTransfer(let id): try type(.cancelTransfer); try values.encode(id, forKey: .id)
        case .retryTransfer(let id): try type(.retryTransfer); try values.encode(id, forKey: .id)
        case .cleanFinishedTransfers: try type(.cleanFinishedTransfers)
        case .requestExtraction(let id): try type(.requestExtraction); try values.encode(id, forKey: .remoteFileID)
        case .openRemoteFolder(let id): try type(.openRemoteFolder); try values.encode(id, forKey: .remoteFileID)
        case .goBackRemoteFolder: try type(.goBackRemoteFolder)
        case .deleteRemoteFile(let id): try type(.deleteRemoteFile); try values.encode(id, forKey: .remoteFileID)
        case .enqueueLocalSync(let id): try type(.enqueueLocalSync); try values.encode(id, forKey: .remoteFileID)
        case .organizeLocalJob(let id): try type(.organizeLocalJob); try values.encode(id, forKey: .id)
        case .refreshWatchlist: try type(.refreshWatchlist)
        case .clearFailedJobs: try type(.clearFailedJobs)
        case .clearHistory: try type(.clearHistory)
        }
    }
}

// MARK: - Pairing

public struct CargoPairingLink: Equatable, Sendable {
    public let serverURL: String
    public let token: String

    public init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
    }

    public init?(parsing string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(parsing: url)
    }

    public init?(parsing url: URL) {
        guard url.scheme?.lowercased() == "cargo", url.host?.lowercased() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let serverURL = items.first(where: { $0.name == "url" })?.value, !serverURL.isEmpty,
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
        self.serverURL = serverURL
        self.token = token
    }

    public var urlString: String {
        var components = URLComponents()
        components.scheme = "cargo"
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "url", value: serverURL), URLQueryItem(name: "token", value: token)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.string ?? "cargo://pair"
    }
}

// MARK: - HTTP client

public final class CargoRemoteAPIClient: @unchecked Sendable {
    public enum ClientError: LocalizedError, Equatable, Sendable {
        case invalidResponse
        case api(CargoAPIError)
        case malformedResponse

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: "Cargo returned an invalid HTTP response."
            case .api(let error): "Cargo API error \(error.code): \(error.message)"
            case .malformedResponse: "Cargo returned malformed API data."
            }
        }
    }

    public let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func discover(at baseURL: URL, session: URLSession = .shared) async throws -> CargoRemoteDiscovery {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/discovery"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 300 else { throw ClientError.invalidResponse }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(CargoAPIEnvelope<CargoRemoteDiscovery>.self, from: data)
        guard envelope.ok, let discovery = envelope.data, discovery.service == "Cargo" else { throw ClientError.malformedResponse }
        return discovery
    }

    public func health() async throws -> CargoAPIHealth { try await get("v1/health") }
    public func snapshot() async throws -> CargoRemoteSnapshot { try await get("v1/state") }
    public func presence() async throws -> CargoRemotePresence { try await get("v1/presence") }
    public func events(since: UInt64? = nil) async throws -> CargoRemoteEvent {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)
        if let since { components?.queryItems = [URLQueryItem(name: "since", value: String(since))] }
        guard let url = components?.url else { throw ClientError.invalidResponse }
        return try await request(url: url)
    }

    public func registerPresence(_ registration: CargoRemotePresenceRegistration) async throws -> CargoRemotePresence {
        try await post("v1/presence/register", body: registration)
    }

    public func heartbeatPresence(clientID: UUID) async throws -> CargoRemotePresence {
        try await post("v1/presence/heartbeat", body: CargoRemotePresenceHeartbeat(id: clientID))
    }

    public func unregisterPresence(clientID: UUID) async throws -> CargoRemotePresence {
        try await post("v1/presence/unregister", body: CargoRemotePresenceHeartbeat(id: clientID))
    }

    public func search(query: String) async throws -> CargoRemoteSearchState {
        try await post("v1/discover/search", body: CargoAPISearchRequest(query: query))
    }

    public func execute(_ command: CargoRemoteCommand) async throws -> CargoRemoteSnapshot {
        try await post("v1/commands", body: command)
    }

    private func get<Payload: Codable & Sendable>(_ path: String) async throws -> Payload {
        try await request(url: baseURL.appendingPathComponent(path))
    }

    private func post<Body: Encodable & Sendable, Payload: Codable & Sendable>(_ path: String, body: Body) async throws -> Payload {
        try await request(url: baseURL.appendingPathComponent(path), method: "POST", body: encoder.encode(body))
    }

    private func request<Payload: Codable & Sendable>(url: URL, method: String = "GET", body: Data? = nil) async throws -> Payload {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        let envelope: CargoAPIEnvelope<Payload>
        do { envelope = try decoder.decode(CargoAPIEnvelope<Payload>.self, from: data) }
        catch { throw ClientError.malformedResponse }
        guard http.statusCode < 300, envelope.ok, let payload = envelope.data else {
            throw ClientError.api(envelope.error ?? CargoAPIError(code: "invalid_response", message: "Cargo returned an unsuccessful response."))
        }
        return payload
    }
}
