import EasySubsKit
import Foundation

/// Subtitles for a video, two sources in order of trust:
/// 1. Put.io's own subtitles for the remote file (already matched to the release),
///    fetched while the remote copy still exists and parked until the file is organized;
/// 2. OpenSubtitles through EasySubsKit — hash match first, filename second.
/// Result lands as `Video.srt` beside the video, which is what Infuse reads.
@MainActor
final class SubtitleService {
    enum Outcome: Equatable {
        case alreadyPresent
        case saved(URL, source: String)
        case noCredentials
        case notFound(String)
    }

    private let client = OpenSubtitlesClient(userAgent: "Cargo")
    private let parkingDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cargo/subtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        parkingDirectory = base
    }

    static func sidecarURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("srt")
    }

    static func hasSubtitle(_ video: URL) -> Bool {
        let base = video.deletingPathExtension()
        let directory = video.deletingLastPathComponent()
        let stem = base.lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return siblings.contains { $0.hasPrefix(stem + ".") && $0.lowercased().hasSuffix(".srt") }
    }

    /// Put.io subtitle for `remoteFileID`, kept in Application Support until `claimParked` runs.
    func park(putIOSubtitle data: Data, remoteFileID: Int) throws {
        try data.write(to: parkingDirectory.appendingPathComponent("\(remoteFileID).srt"), options: .atomic)
    }

    func claimParked(remoteFileID: Int, for video: URL) -> URL? {
        let parked = parkingDirectory.appendingPathComponent("\(remoteFileID).srt")
        guard FileManager.default.fileExists(atPath: parked.path) else { return nil }
        let destination = Self.sidecarURL(for: video)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.moveItem(at: parked, to: destination)) != nil else { return nil }
        return destination
    }

    func fetchFromOpenSubtitles(for video: URL, language: String, credentials: OpenSubtitlesCredentials) async -> Outcome {
        guard !Self.hasSubtitle(video) else { return .alreadyPresent }
        guard credentials.isComplete else { return .noCredentials }
        do {
            let match = try await client.findBestSubtitle(for: video, language: language, credentials: credentials) {}
            let data = try await client.download(match: match, credentials: credentials)
            let destination = Self.sidecarURL(for: video)
            try data.write(to: destination, options: .atomic)
            return .saved(destination, source: match.matchedByHash ? "OpenSubtitles · hash match" : "OpenSubtitles · name match")
        } catch {
            return .notFound(error.localizedDescription)
        }
    }
}
