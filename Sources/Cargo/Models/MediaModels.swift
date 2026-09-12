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
        case .needsReview: "Needs review"
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
    var type: RemoteFileType
    var parentID: Int
    var sizeBytes: Int64
    var createdAt: Date

    var isFolder: Bool {
        type == .folder
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

struct CargoSettings: Codable, Equatable, Sendable {
    var putIOClientID: String?
    var libraryRootBookmark: Data?
    var libraryRootPath: String?
    var stagingDirectoryName: String
    var moviesDirectoryName: String
    var tvShowsDirectoryName: String

    init(
        putIOClientID: String? = nil,
        libraryRootBookmark: Data? = nil,
        libraryRootPath: String? = nil,
        stagingDirectoryName: String = ".cargo-incoming",
        moviesDirectoryName: String = "Movies",
        tvShowsDirectoryName: String = "TV Shows"
    ) {
        self.putIOClientID = putIOClientID
        self.libraryRootBookmark = libraryRootBookmark
        self.libraryRootPath = libraryRootPath
        self.stagingDirectoryName = stagingDirectoryName
        self.moviesDirectoryName = moviesDirectoryName
        self.tvShowsDirectoryName = tvShowsDirectoryName
    }

    static let `default` = CargoSettings()

    var hasLibraryRoot: Bool {
        libraryRootBookmark != nil || libraryRootPath != nil
    }
}

struct CargoState: Codable, Sendable {
    var transfers: [RemoteTransfer]
    var remoteFiles: [RemoteFile]
    var localJobs: [LocalSyncJob]
    var settings: CargoSettings
    var lastUpdated: Date

    init(
        transfers: [RemoteTransfer],
        remoteFiles: [RemoteFile] = [],
        localJobs: [LocalSyncJob],
        settings: CargoSettings = .default,
        lastUpdated: Date
    ) {
        self.transfers = transfers
        self.remoteFiles = remoteFiles
        self.localJobs = localJobs
        self.settings = settings
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transfers = try container.decode([RemoteTransfer].self, forKey: .transfers)
        remoteFiles = try container.decodeIfPresent([RemoteFile].self, forKey: .remoteFiles) ?? []
        localJobs = try container.decode([LocalSyncJob].self, forKey: .localJobs)
        settings = try container.decodeIfPresent(CargoSettings.self, forKey: .settings) ?? .default
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    private enum CodingKeys: String, CodingKey {
        case transfers
        case remoteFiles
        case localJobs
        case settings
        case lastUpdated
    }

    static let demo = CargoState(
        transfers: [
            RemoteTransfer(
                id: 1001,
                name: "The Example Show - S02E04",
                status: .downloading,
                progress: 0.68,
                sizeBytes: 1_900_000_000,
                updatedAt: Date()
            ),
            RemoteTransfer(
                id: 1002,
                name: "Example Movie (2026)",
                status: .completed,
                progress: 1,
                sizeBytes: 7_400_000_000,
                updatedAt: Date()
            )
        ],
        remoteFiles: [
            RemoteFile(
                id: 2001,
                name: "Example Movie (2026).mkv",
                type: .video,
                parentID: 0,
                sizeBytes: 7_400_000_000,
                createdAt: Date()
            ),
            RemoteFile(
                id: 2002,
                name: "Example Show",
                type: .folder,
                parentID: 0,
                sizeBytes: 0,
                createdAt: Date()
            )
        ],
        localJobs: [
            LocalSyncJob(
                id: UUID(),
                remoteFileID: 1002,
                name: "Example Movie (2026)",
                status: .queued,
                progress: 0,
                destination: "Movies/Example Movie (2026)",
                errorMessage: nil,
                updatedAt: Date()
            )
        ],
        lastUpdated: Date()
    )
}
