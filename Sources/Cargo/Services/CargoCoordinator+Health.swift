import Foundation

/// The last inventory walk, unfiltered: every file Put.io listed, by folder.
struct RemoteInventoryIndex {
    /// Folder ID → its full listing. 0 is the root.
    private(set) var children: [Int: [RemoteFile]] = [:]
    private(set) var extraVideoIDs: Set<Int> = []
    private var filesByID: [Int: RemoteFile] = [:]

    init() {}

    init(children: [Int: [RemoteFile]], extraVideoIDs: Set<Int>) {
        self.children = children
        self.extraVideoIDs = extraVideoIDs
        for file in children.values.joined() { filesByID[file.id] = file }
    }

    func file(id: Int) -> RemoteFile? {
        filesByID[id]
    }

    func descendants(of folderID: Int) -> [RemoteFile] {
        var result: [RemoteFile] = []
        var queue = [folderID]
        while let id = queue.popLast() {
            for file in children[id] ?? [] {
                result.append(file)
                if file.isFolder { queue.append(file.id) }
            }
        }
        return result
    }
}

/// Shared index of movies and TV episodes already held by the library, active
/// local jobs, and optionally live Put.io transfers. Both duplicate-release
/// filtering and `isEpisodeKnown(imdbID:season:episode:)` query this index.
struct KnownMediaIndex: Sendable {
    private struct EpisodeRecord: Sendable {
        let year: Int?
        let season: Int
        let episode: Int
        let holder: String
    }

    private var moviesByKey: [String: String] = [:]
    private var episodesByShow: [String: [EpisodeRecord]] = [:]

    mutating func insertLibraryItem(_ item: LibraryItem) {
        switch item.kind {
        case .movie:
            let key = LibraryOrganizer.libraryKey(movie: item.displayTitle)
            if moviesByKey[key] == nil {
                moviesByKey[key] = item.relativePath
            }
        case .show:
            let showKey = CargoTitleMatch.normalize(item.title)
            guard !showKey.isEmpty else { return }
            for (season, episodes) in item.episodes {
                for episode in episodes {
                    let holder = String(format: "%@ S%02dE%02d", item.relativePath, season, episode)
                    insertEpisode(showKey: showKey, year: item.year, season: season, episode: episode, holder: holder)
                }
            }
        }
    }

    mutating func insertMediaFileName(_ fileName: String, holder: String, settings: CargoSettings) {
        let preview = LibraryOrganizer.preview(for: fileName, settings: settings)
        switch preview.kind {
        case .tvEpisode:
            guard let parsed = LibraryOrganizer.parsedEpisode(from: fileName) else { return }
            let showKey = CargoTitleMatch.normalize(parsed.showTitle)
            guard !showKey.isEmpty else { return }
            insertEpisode(showKey: showKey, year: parsed.year, season: parsed.season, episode: parsed.episode, holder: holder)
        case .movie:
            guard let key = LibraryOrganizer.libraryKey(for: fileName, settings: settings),
                  moviesByKey[key] == nil else { return }
            moviesByKey[key] = holder
        case .review:
            break
        }
    }

    mutating func insertTransferName(_ transferName: String, holder: String) {
        guard let parsed = LibraryOrganizer.parsedEpisode(from: transferName) else { return }
        let showKey = CargoTitleMatch.normalize(parsed.showTitle)
        guard !showKey.isEmpty else { return }
        insertEpisode(showKey: showKey, year: parsed.year, season: parsed.season, episode: parsed.episode, holder: holder)
    }

    func holder(forFileName fileName: String, settings: CargoSettings) -> String? {
        let preview = LibraryOrganizer.preview(for: fileName, settings: settings)
        switch preview.kind {
        case .tvEpisode:
            guard let parsed = LibraryOrganizer.parsedEpisode(from: fileName) else { return nil }
            return holder(forEpisodeOfShow: parsed.showTitle, year: parsed.year, season: parsed.season, episode: parsed.episode)
        case .movie:
            guard let key = LibraryOrganizer.libraryKey(for: fileName, settings: settings) else { return nil }
            return moviesByKey[key]
        case .review:
            return nil
        }
    }

    func holder(forEpisodeOfShow showTitle: String, year: Int?, season: Int, episode: Int) -> String? {
        let showKey = CargoTitleMatch.normalize(showTitle)
        guard !showKey.isEmpty, let records = episodesByShow[showKey] else { return nil }
        return records.first {
            $0.season == season && $0.episode == episode && Self.yearsCompatible($0.year, year)
        }?.holder
    }

    private mutating func insertEpisode(showKey: String, year: Int?, season: Int, episode: Int, holder: String) {
        let existing = episodesByShow[showKey] ?? []
        if existing.contains(where: { $0.season == season && $0.episode == episode && $0.year == year }) {
            return
        }
        episodesByShow[showKey, default: []].append(
            EpisodeRecord(year: year, season: season, episode: episode, holder: holder)
        )
    }

    private static func yearsCompatible(_ lhs: Int?, _ rhs: Int?) -> Bool {
        lhs == nil || rhs == nil || lhs == rhs
    }
}

// Transfer health, leftover Put.io copies and duplicate releases.
extension CargoCoordinator {
    /// A downloading torrent with no peers and no data for this long is dead.
    static let noPeersStallInterval: TimeInterval = 6 * 3600
    /// A transfer at 100% that Put.io has not finished for this long is stuck.
    static let finishingStallInterval: TimeInterval = 3600
    /// After a restart the timers start again. A transfer that is already old
    /// enough is flagged once its condition has held this long.
    static let stallConfirmationInterval: TimeInterval = 15 * 60

    /// Sets `problem` on each transfer and warns once in History.
    func assessTransfers(now: Date = Date()) {
        let liveIDs = Set(state.transfers.map(\.id))
        transferStallSince = transferStallSince.filter { liveIDs.contains($0.key) }
        state.noticeKeys.removeAll { key in
            guard let id = Self.noticeID(key, prefixes: ["transfer:", "video:"]) else { return false }
            return !liveIDs.contains(id)
        }

        for index in state.transfers.indices {
            let transfer = state.transfers[index]
            let problem = transferProblem(transfer, now: now)
            state.transfers[index].problem = problem?.text
            guard let problem, problem.warns else { continue }
            let key = "transfer:\(transfer.id)"
            guard !state.noticeKeys.contains(key) else { continue }
            state.noticeKeys.append(key)
            recordHistory(kind: .warning, title: problem.title, detail: "\(transfer.name): \(problem.text)")
        }
    }

    private func transferProblem(_ transfer: RemoteTransfer, now: Date) -> (title: String, text: String, warns: Bool)? {
        switch transfer.status {
        case .failed:
            // The event feed already records the failure in History.
            return ("Put.io transfer failed", transfer.errorMessage ?? "Put.io reports an error.", false)
        case .completed, .seeding:
            transferStallSince[transfer.id] = nil
            return videoProblem(transfer).map { ("Transfer holds no usable video", $0, true) }
        case .cancelled:
            transferStallSince[transfer.id] = nil
            return nil
        case .waiting, .downloading, .unknown:
            break
        }

        let finishing = transfer.progress >= 1
        let deadSwarm = transfer.status == .downloading
            && (transfer.peersConnected ?? 0) == 0
            && (transfer.downloadSpeed ?? 0) == 0
        guard finishing || deadSwarm else {
            transferStallSince[transfer.id] = nil
            return transfer.errorMessage.map { ("Put.io transfer error", $0, false) }
        }
        let since = transferStallSince[transfer.id] ?? now
        transferStallSince[transfer.id] = since
        let threshold = finishing ? Self.finishingStallInterval : Self.noPeersStallInterval
        let held = now.timeIntervalSince(since)
        let age = transfer.createdAt.map { now.timeIntervalSince($0) } ?? 0
        guard held >= threshold || (age >= threshold && held >= Self.stallConfirmationInterval) else { return nil }
        let text = finishing
            ? "Stuck at 100%: Put.io has not finished it. Retry or cancel it."
            : "No peers and no data. The torrent may be dead."
        return ("Transfer looks stuck", transfer.errorMessage.map { "\(text) Put.io: \($0)" } ?? text, true)
    }

    /// A finished transfer whose file or folder is still on Put.io but holds
    /// nothing Cargo downloads. Put.io types a broken .mkv as FILE, which
    /// Cargo skips, so without this the release just sits there.
    private func videoProblem(_ transfer: RemoteTransfer) -> String? {
        guard transfer.userFileExists == true,
              let fileID = transfer.fileID,
              let root = inventoryIndex.file(id: fileID) else { return nil }
        let videoKey = "video:\(transfer.id)"
        guard !state.noticeKeys.contains(videoKey) else { return nil }

        let files = root.isFolder ? inventoryIndex.descendants(of: fileID) : [root]
        var usable = Set(state.remoteMediaFiles.map(\.id))
        usable.formUnion(state.remoteArchiveFiles.map(\.id))
        usable.formUnion(inventoryIndex.extraVideoIDs)
        usable.formUnion(state.localJobs.map(\.remoteFileID))
        if files.contains(where: { usable.contains($0.id) }) {
            // Once Cargo has taken the videos, the leftovers are not a problem.
            state.noticeKeys.append(videoKey)
            return nil
        }
        if let suspect = files.first(where: { !$0.isFolder && LibraryOrganizer.isMediaFile(named: $0.name) }) {
            return "Put.io finished it, but does not see \(suspect.name) as a video. The file may be broken."
        }
        return "Put.io finished it, but it holds no video."
    }

    /// Completed jobs whose Put.io copy is still there, because the delete
    /// after the download failed or never ran. Verifies the local copy again,
    /// then sends the Put.io copy to the trash.
    func removeLeftoverRemoteCopies() async {
        guard state.settings.automaticRemoteCleanupEnabled else { return }
        let remoteByID = Dictionary(state.remoteMediaFiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        state.noticeKeys.removeAll { key in
            guard let id = Self.noticeID(key, prefixes: ["leftover:"]) else { return false }
            return remoteByID[id] == nil
        }
        let jobs = state.localJobs.filter { job in
            [.completed, .needsReview].contains(job.status)
                && remoteByID[job.remoteFileID] != nil
                && !state.noticeKeys.contains("leftover:\(job.remoteFileID)")
        }
        guard !jobs.isEmpty, let rootURL = libraryRootURL() else { return }
        let accessing = rootURL.startAccessingSecurityScopedResource()
        defer { if accessing { rootURL.stopAccessingSecurityScopedResource() } }

        for job in jobs {
            guard let remote = remoteByID[job.remoteFileID] else { continue }
            do {
                guard let path = job.destination else { throw SettingsError.localCopyMissing }
                let localURL = URL(fileURLWithPath: path)
                try verifyLocalCopy(remoteFileID: remote.id, localURL: localURL)
                try await verifyLocalContent(remoteFileID: remote.id, localURL: localURL)
                try await deleteRemoteFile(
                    remoteFileID: remote.id,
                    reason: "\(remote.displayPath) · left over after a verified copy"
                )
            } catch {
                state.noticeKeys.append("leftover:\(remote.id)")
                recordHistory(
                    kind: .warning,
                    title: "Kept a Put.io copy Cargo already downloaded",
                    detail: "\(remote.displayPath): \(error.localizedDescription)"
                )
            }
        }
        persistQuietly()
    }

    /// Builds the shared index of already-known movies and TV episodes from
    /// the library, active local jobs, and optionally live Put.io transfers.
    func knownMediaIndex(includeTransfers: Bool) -> KnownMediaIndex {
        let settings = state.settings
        var index = KnownMediaIndex()

        for item in state.libraryItems {
            index.insertLibraryItem(item)
        }
        for job in state.localJobs {
            switch job.status {
            case .queued, .downloading, .importing:
                break
            case .needsReview:
                // Only a file that is still in the inbox counts.
                guard let path = job.destination, FileManager.default.fileExists(atPath: path) else { continue }
            case .completed, .failed:
                continue
            }
            index.insertMediaFileName(job.name, holder: job.name, settings: settings)
        }
        if includeTransfers {
            for transfer in state.transfers where Self.isKnownTransfer(transfer) {
                index.insertTransferName(transfer.name, holder: transfer.name)
            }
        }
        return index
    }

    private static func isKnownTransfer(_ transfer: RemoteTransfer) -> Bool {
        switch transfer.status {
        case .waiting, .downloading, .seeding:
            return true
        case .completed:
            return transfer.userFileExists != false
        case .failed, .cancelled, .unknown:
            return false
        }
    }

    /// Splits new Put.io media into what to download and what the library or
    /// a running job already has. Of two new releases of one episode, the
    /// larger file wins.
    func splitDuplicateReleases(_ files: [RemoteFile]) -> (wanted: [RemoteFile], duplicates: [(file: RemoteFile, holder: String)]) {
        let settings = state.settings
        var index = knownMediaIndex(includeTransfers: false)

        var duplicateIDs: [Int: String] = [:]
        for file in files.sorted(by: { $0.sizeBytes > $1.sizeBytes }) {
            if let holder = index.holder(forFileName: file.name, settings: settings) {
                duplicateIDs[file.id] = holder
            } else {
                index.insertMediaFileName(file.name, holder: file.name, settings: settings)
            }
        }
        let wanted = files.filter { duplicateIDs[$0.id] == nil }
        let duplicates = files.compactMap { file in duplicateIDs[file.id].map { (file: file, holder: $0) } }
        return (wanted, duplicates)
    }

    /// Sends duplicate releases to Put.io's trash, so a wrong call stays
    /// recoverable. With cleanup off, it only records them.
    func removeDuplicateReleases(_ duplicates: [(file: RemoteFile, holder: String)]) async {
        for (file, holder) in duplicates {
            let reason = "\(file.displayPath) · duplicate of \(holder)"
            guard state.settings.automaticRemoteCleanupEnabled else {
                recordHistory(kind: .info, title: "Skipped duplicate release", detail: reason)
                continue
            }
            do {
                try await deleteRemoteFile(remoteFileID: file.id, reason: reason)
            } catch {
                recordHistory(kind: .warning, title: "Could not remove duplicate release", detail: "\(reason): \(error.localizedDescription)")
            }
        }
    }

    private static func noticeID(_ key: String, prefixes: [String]) -> Int? {
        guard let prefix = prefixes.first(where: key.hasPrefix) else { return nil }
        return Int(key.dropFirst(prefix.count))
    }
}
