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
    case archive
    case other
    case unknown

    var displayName: String {
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

    var isArchive: Bool {
        type == .archive
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
    /// Ask Put.io to unpack archives it finds (rar'd releases) so the video inside shows up.
    var automaticExtractEnabled: Bool
    /// `transfers/clean` after each cycle: finished transfers stop piling up on Put.io.
    var automaticTransferCleanEnabled: Bool
    /// Subtitles after organizing: Put.io's own first, then OpenSubtitles (EasySubsKit).
    var automaticSubtitlesEnabled: Bool
    var subtitleLanguage: String
    var openSubtitlesUsername: String
    var openSubtitlesAPIKey: String
    var imdbWatchlistURL: String
    /// How often the background cycle polls Put.io and the watchlist.
    var refreshIntervalMinutes: Int

    static let refreshIntervalChoices = [1, 5, 10, 30]

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
        automaticExtractEnabled: Bool = true,
        automaticTransferCleanEnabled: Bool = false,
        automaticSubtitlesEnabled: Bool = true,
        subtitleLanguage: String = "en",
        openSubtitlesUsername: String = "",
        openSubtitlesAPIKey: String = "",
        imdbWatchlistURL: String = "https://www.imdb.com/user/p.cmhfeyepnnf4jl2m4wk7q2qz3q/watchlist/",
        refreshIntervalMinutes: Int = 1
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
        self.automaticExtractEnabled = automaticExtractEnabled
        self.automaticTransferCleanEnabled = automaticTransferCleanEnabled
        self.automaticSubtitlesEnabled = automaticSubtitlesEnabled
        self.subtitleLanguage = subtitleLanguage
        self.openSubtitlesUsername = openSubtitlesUsername
        self.openSubtitlesAPIKey = openSubtitlesAPIKey
        self.imdbWatchlistURL = imdbWatchlistURL
        self.refreshIntervalMinutes = refreshIntervalMinutes
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
        case automaticExtractEnabled
        case automaticTransferCleanEnabled
        case automaticSubtitlesEnabled
        case subtitleLanguage
        case openSubtitlesUsername
        case openSubtitlesAPIKey
        case imdbWatchlistURL
        case refreshIntervalMinutes
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
        automaticExtractEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticExtractEnabled) ?? true
        automaticTransferCleanEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticTransferCleanEnabled) ?? false
        automaticSubtitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticSubtitlesEnabled) ?? true
        subtitleLanguage = try container.decodeIfPresent(String.self, forKey: .subtitleLanguage) ?? "en"
        openSubtitlesUsername = try container.decodeIfPresent(String.self, forKey: .openSubtitlesUsername) ?? ""
        openSubtitlesAPIKey = try container.decodeIfPresent(String.self, forKey: .openSubtitlesAPIKey) ?? ""
        imdbWatchlistURL = try container.decodeIfPresent(String.self, forKey: .imdbWatchlistURL)
            ?? "https://www.imdb.com/user/p.cmhfeyepnnf4jl2m4wk7q2qz3q/watchlist/"
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 1
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
    /// Archives seen in Put.io (rar'd releases) and the ones we asked it to unpack.
    var remoteArchiveFiles: [RemoteFile]
    var requestedExtractionFileIDs: [Int]
    /// Last `events/list` id we processed; only newer events count.
    var lastPutIOEventID: Int?
    /// The SSD, as last scanned; and TMDB metadata keyed by library item id or IMDb id.
    var libraryItems: [LibraryItem]
    var metadata: [String: TMDBMetadata]
    /// Lookups TMDB had nothing for, and when; retried after a week, not every cycle.
    var metadataMisses: [String: Date]
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
        remoteArchiveFiles: [RemoteFile] = [],
        requestedExtractionFileIDs: [Int] = [],
        lastPutIOEventID: Int? = nil,
        libraryItems: [LibraryItem] = [],
        metadata: [String: TMDBMetadata] = [:],
        metadataMisses: [String: Date] = [:],
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
        self.remoteArchiveFiles = remoteArchiveFiles
        self.requestedExtractionFileIDs = requestedExtractionFileIDs
        self.lastPutIOEventID = lastPutIOEventID
        self.libraryItems = libraryItems
        self.metadata = metadata
        self.metadataMisses = metadataMisses
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
        remoteArchiveFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteArchiveFiles) ?? []
        requestedExtractionFileIDs = try container.decodeIfPresent([Int].self, forKey: .requestedExtractionFileIDs) ?? []
        lastPutIOEventID = try container.decodeIfPresent(Int.self, forKey: .lastPutIOEventID)
        libraryItems = try container.decodeIfPresent([LibraryItem].self, forKey: .libraryItems) ?? []
        metadata = try container.decodeIfPresent([String: TMDBMetadata].self, forKey: .metadata) ?? [:]
        metadataMisses = try container.decodeIfPresent([String: Date].self, forKey: .metadataMisses) ?? [:]
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
        case remoteArchiveFiles
        case requestedExtractionFileIDs
        case lastPutIOEventID
        case libraryItems
        case metadata
        case metadataMisses
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
