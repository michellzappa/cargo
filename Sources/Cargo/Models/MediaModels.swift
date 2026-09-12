import Foundation

enum RemoteTransferStatus: String, Codable, Sendable {
    case waiting
    case downloading
    case seeding
    case completed
    case failed
    case cancelled
    case unknown

    var displayName: String {
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

enum LocalSyncStatus: String, Codable, Sendable {
    case queued
    case downloading
    case importing
    case completed
    case needsReview
    case failed

    var displayName: String {
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

enum RemoteFileType: String, Codable, Sendable {
    case folder
    case video
    case audio
    case image
    case pdf
    case other
    case unknown

    var displayName: String {
        switch self {
        case .folder: "Folder"
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        case .pdf: "PDF"
        case .other: "File"
        case .unknown: "Unknown"
        }
    }
}

struct RemoteTransfer: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
    var status: RemoteTransferStatus
    var progress: Double
    var sizeBytes: Int64
    var updatedAt: Date
}

struct RemoteFile: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
    var path: String? = nil
    var type: RemoteFileType
    var parentID: Int
    var sizeBytes: Int64
    var createdAt: Date

    var isFolder: Bool {
        type == .folder
    }

    var isMediaFile: Bool {
        type == .video
    }

    var displayPath: String {
        path ?? name
    }
}

struct IMDbWatchlistItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var year: Int?
    var titleType: String?
    var addedAt: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case titleType
        case addedAt
    }

    init(
        id: String,
        title: String,
        year: Int? = nil,
        titleType: String? = nil,
        addedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.titleType = titleType
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        titleType = try container.decodeIfPresent(String.self, forKey: .titleType)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
    }
}

struct LocalSyncJob: Codable, Identifiable, Sendable {
    let id: UUID
    var remoteFileID: Int
    var name: String
    var status: LocalSyncStatus
    var progress: Double
    var destination: String?
    var errorMessage: String?
    var updatedAt: Date
}

enum CargoHistoryKind: String, Codable, Sendable {
    case info
    case success
    case warning
    case failure
}

struct CargoHistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let kind: CargoHistoryKind
    let title: String
    let detail: String
}

struct CargoSettings: Codable, Equatable, Sendable {
    var libraryRootBookmark: Data?
    var libraryRootPath: String?
    var stagingDirectoryName: String
    var moviesDirectoryName: String
    var tvShowsDirectoryName: String
    var automaticSyncEnabled: Bool
    var automaticOrganizationEnabled: Bool
    var notificationsEnabled: Bool
    var launchAtLoginEnabled: Bool
    var automaticRemoteCleanupEnabled: Bool
    var automaticInboxCleanupEnabled: Bool
    var imdbWatchlistURL: String

    init(
        libraryRootBookmark: Data? = nil,
        libraryRootPath: String? = nil,
        stagingDirectoryName: String = "_Inbox",
        moviesDirectoryName: String = "Movies",
        tvShowsDirectoryName: String = "TV Shows",
        automaticSyncEnabled: Bool = true,
        automaticOrganizationEnabled: Bool = true,
        notificationsEnabled: Bool = true,
        launchAtLoginEnabled: Bool = true,
        automaticRemoteCleanupEnabled: Bool = true,
        automaticInboxCleanupEnabled: Bool = true,
        imdbWatchlistURL: String = "https://www.imdb.com/user/p.cmhfeyepnnf4jl2m4wk7q2qz3q/watchlist/"
    ) {
        self.libraryRootBookmark = libraryRootBookmark
        self.libraryRootPath = libraryRootPath
        self.stagingDirectoryName = stagingDirectoryName
        self.moviesDirectoryName = moviesDirectoryName
        self.tvShowsDirectoryName = tvShowsDirectoryName
        self.automaticSyncEnabled = automaticSyncEnabled
        self.automaticOrganizationEnabled = automaticOrganizationEnabled
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.automaticRemoteCleanupEnabled = automaticRemoteCleanupEnabled
        self.automaticInboxCleanupEnabled = automaticInboxCleanupEnabled
        self.imdbWatchlistURL = imdbWatchlistURL
    }

    private enum CodingKeys: String, CodingKey {
        case libraryRootBookmark
        case libraryRootPath
        case stagingDirectoryName
        case moviesDirectoryName
        case tvShowsDirectoryName
        case automaticSyncEnabled
        case automaticOrganizationEnabled
        case notificationsEnabled
        case launchAtLoginEnabled
        case automaticRemoteCleanupEnabled
        case automaticInboxCleanupEnabled
        case imdbWatchlistURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        libraryRootBookmark = try container.decodeIfPresent(Data.self, forKey: .libraryRootBookmark)
        libraryRootPath = try container.decodeIfPresent(String.self, forKey: .libraryRootPath)
        stagingDirectoryName = try container.decodeIfPresent(String.self, forKey: .stagingDirectoryName) ?? "_Inbox"
        moviesDirectoryName = try container.decodeIfPresent(String.self, forKey: .moviesDirectoryName) ?? "Movies"
        tvShowsDirectoryName = try container.decodeIfPresent(String.self, forKey: .tvShowsDirectoryName) ?? "TV Shows"
        automaticSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticSyncEnabled) ?? true
        automaticOrganizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticOrganizationEnabled) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? true
        automaticRemoteCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticRemoteCleanupEnabled) ?? true
        automaticInboxCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticInboxCleanupEnabled) ?? true
        imdbWatchlistURL = try container.decodeIfPresent(String.self, forKey: .imdbWatchlistURL)
            ?? "https://www.imdb.com/user/p.cmhfeyepnnf4jl2m4wk7q2qz3q/watchlist/"
    }

    static let `default` = CargoSettings()

    var hasLibraryRoot: Bool {
        libraryRootBookmark != nil || libraryRootPath != nil
    }
}

struct CargoState: Codable, Sendable {
    var transfers: [RemoteTransfer]
    var remoteFiles: [RemoteFile]
    var remoteMediaFiles: [RemoteFile]
    var remoteFolders: [RemoteFile]
    var localJobs: [LocalSyncJob]
    var history: [CargoHistoryEntry]
    var seenRemoteMediaFileIDs: [Int]
    var remoteMediaBaselineEstablished: Bool
    var imdbWatchlistItems: [IMDbWatchlistItem]
    var imdbWatchlistLastUpdated: Date?
    var deletedRemoteFileIDs: [Int]
    var deletedRemoteFolderIDs: [Int]
    var settings: CargoSettings
    var lastUpdated: Date

    init(
        transfers: [RemoteTransfer],
        remoteFiles: [RemoteFile] = [],
        remoteMediaFiles: [RemoteFile] = [],
        remoteFolders: [RemoteFile] = [],
        localJobs: [LocalSyncJob],
        history: [CargoHistoryEntry] = [],
        seenRemoteMediaFileIDs: [Int] = [],
        remoteMediaBaselineEstablished: Bool = false,
        imdbWatchlistItems: [IMDbWatchlistItem] = [],
        imdbWatchlistLastUpdated: Date? = nil,
        deletedRemoteFileIDs: [Int] = [],
        deletedRemoteFolderIDs: [Int] = [],
        settings: CargoSettings = .default,
        lastUpdated: Date
    ) {
        self.transfers = transfers
        self.remoteFiles = remoteFiles
        self.remoteMediaFiles = remoteMediaFiles
        self.remoteFolders = remoteFolders
        self.localJobs = localJobs
        self.history = history
        self.seenRemoteMediaFileIDs = seenRemoteMediaFileIDs
        self.remoteMediaBaselineEstablished = remoteMediaBaselineEstablished
        self.imdbWatchlistItems = imdbWatchlistItems
        self.imdbWatchlistLastUpdated = imdbWatchlistLastUpdated
        self.deletedRemoteFileIDs = deletedRemoteFileIDs
        self.deletedRemoteFolderIDs = deletedRemoteFolderIDs
        self.settings = settings
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        transfers = try container.decode([RemoteTransfer].self, forKey: .transfers)
        remoteFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteFiles) ?? []
        remoteMediaFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteMediaFiles) ?? []
        remoteFolders = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteFolders) ?? []
        localJobs = try container.decode([LocalSyncJob].self, forKey: .localJobs)
        history = try container.decodeIfPresent([CargoHistoryEntry].self, forKey: .history) ?? []
        seenRemoteMediaFileIDs = try container.decodeIfPresent([Int].self, forKey: .seenRemoteMediaFileIDs) ?? []
        let currentBaseline = try container.decodeIfPresent(Bool.self, forKey: .remoteMediaBaselineEstablished)
        let legacyBaseline = try legacyContainer.decodeIfPresent(Bool.self, forKey: .backgroundBaselineEstablished)
        remoteMediaBaselineEstablished = currentBaseline ?? legacyBaseline ?? false
        imdbWatchlistItems = try container.decodeIfPresent([IMDbWatchlistItem].self, forKey: .imdbWatchlistItems) ?? []
        imdbWatchlistLastUpdated = try container.decodeIfPresent(Date.self, forKey: .imdbWatchlistLastUpdated)
        deletedRemoteFileIDs = try container.decodeIfPresent([Int].self, forKey: .deletedRemoteFileIDs) ?? []
        deletedRemoteFolderIDs = try container.decodeIfPresent([Int].self, forKey: .deletedRemoteFolderIDs) ?? []
        settings = try container.decodeIfPresent(CargoSettings.self, forKey: .settings) ?? .default
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    private enum CodingKeys: String, CodingKey {
        case transfers
        case remoteFiles
        case remoteMediaFiles
        case remoteFolders
        case localJobs
        case history
        case seenRemoteMediaFileIDs
        case remoteMediaBaselineEstablished
        case imdbWatchlistItems
        case imdbWatchlistLastUpdated
        case deletedRemoteFileIDs
        case deletedRemoteFolderIDs
        case settings
        case lastUpdated
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case backgroundBaselineEstablished
    }

    static let empty = CargoState(
        transfers: [],
        remoteFiles: [],
        localJobs: [],
        lastUpdated: Date()
    )
}
