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

struct RemoteTransfer: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
    var status: RemoteTransferStatus
    var progress: Double
    var sizeBytes: Int64
    var updatedAt: Date
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

struct CargoState: Codable, Sendable {
    var transfers: [RemoteTransfer]
    var localJobs: [LocalSyncJob]
    var lastUpdated: Date

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
