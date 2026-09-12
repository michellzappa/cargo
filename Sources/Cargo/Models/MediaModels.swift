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

    init(
        libraryRootBookmark: Data? = nil,
        libraryRootPath: String? = nil,
        stagingDirectoryName: String = "_Inbox",
        moviesDirectoryName: String = "Movies",
        tvShowsDirectoryName: String = "TV Shows",
        automaticSyncEnabled: Bool = true,
        automaticOrganizationEnabled: Bool = true,
        notificationsEnabled: Bool = true,
        launchAtLoginEnabled: Bool = true
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
    var localJobs: [LocalSyncJob]
    var history: [CargoHistoryEntry]
    var seenRemoteMediaFileIDs: [Int]
    var remoteMediaBaselineEstablished: Bool
    var settings: CargoSettings
    var lastUpdated: Date

    init(
        transfers: [RemoteTransfer],
        remoteFiles: [RemoteFile] = [],
        remoteMediaFiles: [RemoteFile] = [],
        localJobs: [LocalSyncJob],
        history: [CargoHistoryEntry] = [],
        seenRemoteMediaFileIDs: [Int] = [],
        remoteMediaBaselineEstablished: Bool = false,
        settings: CargoSettings = .default,
        lastUpdated: Date
    ) {
        self.transfers = transfers
        self.remoteFiles = remoteFiles
        self.remoteMediaFiles = remoteMediaFiles
        self.localJobs = localJobs
        self.history = history
        self.seenRemoteMediaFileIDs = seenRemoteMediaFileIDs
        self.remoteMediaBaselineEstablished = remoteMediaBaselineEstablished
        self.settings = settings
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        transfers = try container.decode([RemoteTransfer].self, forKey: .transfers)
        remoteFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteFiles) ?? []
        remoteMediaFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteMediaFiles) ?? []
        localJobs = try container.decode([LocalSyncJob].self, forKey: .localJobs)
        history = try container.decodeIfPresent([CargoHistoryEntry].self, forKey: .history) ?? []
        seenRemoteMediaFileIDs = try container.decodeIfPresent([Int].self, forKey: .seenRemoteMediaFileIDs) ?? []
        let currentBaseline = try container.decodeIfPresent(Bool.self, forKey: .remoteMediaBaselineEstablished)
        let legacyBaseline = try legacyContainer.decodeIfPresent(Bool.self, forKey: .backgroundBaselineEstablished)
        remoteMediaBaselineEstablished = currentBaseline ?? legacyBaseline ?? false
        settings = try container.decodeIfPresent(CargoSettings.self, forKey: .settings) ?? .default
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    private enum CodingKeys: String, CodingKey {
        case transfers
        case remoteFiles
        case remoteMediaFiles
        case localJobs
        case history
        case seenRemoteMediaFileIDs
        case remoteMediaBaselineEstablished
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
