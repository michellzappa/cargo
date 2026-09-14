import Foundation
import HouseKit

struct CargoBackgroundCycleSummary: Sendable {
    var discovered: [String] = []
    var watchlistAdded: [String] = []
    var deleted: [String] = []
    var deletedFolders: [String] = []
    var downloaded: [String] = []
    var organized: [String] = []
    var extracting: [String] = []
    var failures: [String] = []

    var hasMeaningfulChanges: Bool {
        !discovered.isEmpty || !watchlistAdded.isEmpty || !deleted.isEmpty || !deletedFolders.isEmpty
            || !downloaded.isEmpty || !organized.isEmpty || !extracting.isEmpty || !failures.isEmpty
    }
}

@MainActor
final class CargoCoordinator {
    enum SettingsError: LocalizedError {
        case emptyDirectoryName
        case invalidIMDbWatchlistURL
        case remoteFileMissing
        case localCopyMissing
        case localCopySizeMismatch
        case inboxFileMissing
        case ambiguousMedia
        case destinationAlreadyExists
        case unableToCreateDestination
        case unableToMoveFile
        case invalidTransferURL
        case libraryRootMissing

        var errorDescription: String? {
            switch self {
            case .invalidTransferURL:
                "Paste a magnet link or a torrent/HTTP URL."
            case .libraryRootMissing:
                "Choose a library folder in Settings first."
            case .emptyDirectoryName:
                "Library folder names cannot be empty."
            case .invalidIMDbWatchlistURL:
                "Enter a public IMDb Watchlist URL."
            case .remoteFileMissing:
                "Cargo no longer has this Put.io file in its current inventory."
            case .localCopyMissing:
                "Cargo could not verify the local copy because it is missing."
            case .localCopySizeMismatch:
                "Cargo did not delete the Put.io file because the local copy size does not match."
            case .inboxFileMissing:
                "The downloaded file is no longer in the Cargo inbox."
            case .ambiguousMedia:
                "Cargo could not determine whether this is a movie or TV episode."
            case .destinationAlreadyExists:
                "A file already exists at the proposed library destination."
            case .unableToCreateDestination:
                "Cargo could not create the proposed library folder."
            case .unableToMoveFile:
                "Cargo could not move the file into the library."
            }
        }
    }

    private let store: CargoStore
    private let keychain = KeychainStore()
    private let imdbWatchlistService = IMDbWatchlistService()
    private var putIOClient: PutIOClient
    private var remoteFolderStack: [(id: Int, name: String)] = []
    private var pendingOAuthState: String?
    /// Posted on the main queue, coalesced, whenever state or status text changes.
    static let didChange = Notification.Name("CargoCoordinator.didChange")

    private(set) var state: CargoState {
        didSet { scheduleChangeNotification() }
    }
    private(set) var putIOStatus = "Not connected yet" {
        didSet { scheduleChangeNotification() }
    }
    private(set) var imdbWatchlistStatus = "Not synced yet" {
        didSet { scheduleChangeNotification() }
    }
    private var changeNotificationScheduled = false
    private(set) var diskUsage: PutIODiskUsage? {
        didSet { scheduleChangeNotification() }
    }
    /// What is sitting in Put.io's trash, refreshed with the account.
    private(set) var trashSummary: PutIOTrashSummary? {
        didSet { scheduleChangeNotification() }
    }
    private(set) var remoteFolderID = 0
    private(set) var remoteFolderName = "Put.io root"

    var canGoBackRemoteFolder: Bool {
        !remoteFolderStack.isEmpty
    }

    init(store: CargoStore = CargoStore(), client: PutIOClient? = nil) {
        self.store = store
        if let client {
            self.putIOClient = client
            self.putIOStatus = "Test client"
        } else if let token = keychain.readToken(), !token.isEmpty {
            self.putIOClient = PutIOAPIClient(token: token)
            self.putIOStatus = "Token saved · not tested"
        } else {
            self.putIOClient = UnconfiguredPutIOClient()
        }
        self.state = store.snapshot()
        if self.state.settings.stagingDirectoryName == ".cargo-incoming" {
            self.state.settings.stagingDirectoryName = "_Inbox"
            try? store.replace(with: self.state)
        }
    }

    func refresh() {
        state = store.snapshot()
    }

    var isConnected: Bool {
        putIOStatus.hasPrefix("Connected as ")
    }

    private func persist() throws {
        state.lastUpdated = Date()
        try store.replace(with: state)
    }

    private func scheduleChangeNotification() {
        guard !changeNotificationScheduled else { return }
        changeNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            changeNotificationScheduled = false
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private func storePutIOAccessToken(_ token: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw PutIOAPIClient.ClientError.missingToken
        }

        try keychain.saveToken(trimmedToken)
        putIOClient = PutIOAPIClient(token: trimmedToken)
        putIOStatus = "Token saved · testing…"
    }

    func beginPutIOAuthorization() throws -> URL {
        let oauthState = UUID().uuidString
        let url = try PutIOOAuth.authorizationURL(state: oauthState)
        pendingOAuthState = oauthState
        try store.replace(with: state)
        putIOStatus = "Waiting for Put.io authorization…"
        return url
    }

    func finishPutIOAuthorization(from callbackURL: URL) async throws {
        guard let pendingOAuthState else {
            throw PutIOOAuth.OAuthError.invalidCallback
        }
        let callback = try PutIOOAuth.parseCallback(callbackURL, expectedState: pendingOAuthState)
        self.pendingOAuthState = nil
        try storePutIOAccessToken(callback.accessToken)
        await refreshFromPutIO()
    }

    func removePutIOToken() throws {
        try keychain.deleteToken()
        putIOClient = UnconfiguredPutIOClient()
        putIOStatus = "Not connected yet"
    }

    func saveLibraryRoot(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        state.settings.libraryRootBookmark = bookmark
        state.settings.libraryRootPath = url.path
        try persist()
    }

    func saveDirectorySettings(staging: String, movies: String, tvShows: String) throws {
        let values = [staging, movies, tvShows].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            throw SettingsError.emptyDirectoryName
        }

        state.settings.stagingDirectoryName = values[0]
        state.settings.moviesDirectoryName = values[1]
        state.settings.tvShowsDirectoryName = values[2]
        try persist()
    }

    func saveIMDbWatchlistURL(_ value: String) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              url.scheme == "https",
              url.host?.lowercased().hasSuffix("imdb.com") == true,
              url.path.lowercased().contains("watchlist") else {
            throw SettingsError.invalidIMDbWatchlistURL
        }

        if state.settings.imdbWatchlistURL != url.absoluteString {
            state.settings.imdbWatchlistURL = url.absoluteString
            state.imdbWatchlistItems = []
            state.imdbWatchlistLastUpdated = nil
        }
        state.lastUpdated = Date()
        imdbWatchlistStatus = "Ready to sync"
        try store.replace(with: state)
    }

    func refreshIMDbWatchlist(force: Bool = true) async -> [String] {
        guard !state.settings.imdbWatchlistURL.isEmpty else {
            imdbWatchlistStatus = "No Watchlist URL"
            return []
        }

        if !force,
           let lastUpdated = state.imdbWatchlistLastUpdated,
           Date().timeIntervalSince(lastUpdated) < 15 * 60 {
            return []
        }

        do {
            let previousIDs = Set(state.imdbWatchlistItems.map(\.id))
            let items = try await imdbWatchlistService.fetchItems(from: state.settings.imdbWatchlistURL)
            state.imdbWatchlistItems = items.sorted {
                if let lhsDate = $0.addedAt, let rhsDate = $1.addedAt, lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                if ($0.addedAt != nil) != ($1.addedAt != nil) {
                    return $0.addedAt != nil
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            state.imdbWatchlistLastUpdated = Date()
            try persist()
            imdbWatchlistStatus = "Updated \(Self.watchlistTimeFormatter.string(from: Date())) · \(items.count) titles"

            let addedItems = items.filter { !previousIDs.contains($0.id) }
            if !addedItems.isEmpty {
                let detail = addedItems.map { item in
                    item.year.map { "\(item.title) (\($0))" } ?? item.title
                }.joined(separator: ", ")
                recordHistory(
                    kind: .info,
                    title: "IMDb Watchlist updated",
                    detail: "Added \(addedItems.count) title\(addedItems.count == 1 ? "" : "s"): \(detail)"
                )
            }
            return addedItems.map(\.title)
        } catch {
            imdbWatchlistStatus = error.localizedDescription
            return []
        }
    }

    func saveWorkflowSettings(
        automaticSync: Bool,
        automaticOrganization: Bool,
        notifications: Bool,
        launchAtLogin: Bool,
        automaticRemoteCleanup: Bool,
        automaticInboxCleanup: Bool
    ) throws {
        try LaunchAtLogin.setEnabled(launchAtLogin)
        state.settings.automaticSyncEnabled = automaticSync
        state.settings.automaticOrganizationEnabled = automaticOrganization
        state.settings.notificationsEnabled = notifications
        state.settings.launchAtLoginEnabled = launchAtLogin
        state.settings.automaticRemoteCleanupEnabled = automaticRemoteCleanup
        state.settings.automaticInboxCleanupEnabled = automaticInboxCleanup
        try persist()
    }

    func updateSettings(_ mutate: (inout CargoSettings) throws -> Void) throws {
        var settings = state.settings
        try mutate(&settings)
        if settings.launchAtLoginEnabled != state.settings.launchAtLoginEnabled {
            try LaunchAtLogin.setEnabled(settings.launchAtLoginEnabled)
        }
        state.settings = settings
        try persist()
    }

    func clearLibraryRoot() throws {
        state.settings.libraryRootBookmark = nil
        state.settings.libraryRootPath = nil
        try persist()
    }

    func libraryRootURL() -> URL? {
        if let bookmark = state.settings.libraryRootBookmark {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolvedURL
            }
        }

        guard let path = state.settings.libraryRootPath else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func inboxFileURLs() -> [URL] {
        guard let rootURL = libraryRootURL() else { return [] }
        let isAccessingScopedResource = rootURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingScopedResource {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let inboxURL = rootURL.appendingPathComponent(
            state.settings.stagingDirectoryName,
            isDirectory: true
        )
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: inboxURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.lastPathComponent != ".DS_Store",
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
                  LibraryOrganizer.isMediaFile(named: url.lastPathComponent) else {
                return nil
            }
            return url
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var cyclesSinceInventoryWalk = 0
    private static let inventoryWalkEvery = 10

    /// Pulls account, transfers and the activity feed. The recursive inventory
    /// walk is the expensive part, so it runs only when something could have
    /// changed: a transfer completed since last time (from the event feed or
    /// the transfer list), an extraction in flight, the first run, an explicit
    /// `force` (the Refresh button) — and every tenth cycle regardless.
    func refreshFromPutIO(force: Bool = true) async {
        do {
            let account = try await putIOClient.fetchAccount()
            let transfers = try await putIOClient.fetchTransfers()
            let remoteFiles = try await putIOClient.fetchFiles(parentID: 0, types: nil)
            let previouslyDone = Set(state.transfers.filter { [.completed, .seeding].contains($0.status) }.map(\.id))
            let newlyDone = transfers.contains { [.completed, .seeding].contains($0.status) && !previouslyDone.contains($0.id) }
            state.transfers = transfers
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)

            let newEvents = try await processPutIOEvents()
            let somethingLanded = newlyDone || newEvents.contains { $0.kind == .transferCompleted }
            cyclesSinceInventoryWalk += 1
            let overdue = cyclesSinceInventoryWalk >= Self.inventoryWalkEvery
            if force || somethingLanded || overdue || !state.remoteMediaBaselineEstablished || !state.requestedExtractionFileIDs.isEmpty {
                cyclesSinceInventoryWalk = 0
                let inventory = try await fetchRemoteInventory()
                state.remoteMediaFiles = inventory.mediaFiles
                state.remoteFolders = inventory.folders
                state.remoteArchiveFiles = inventory.archives
            }
            remoteFolderStack.removeAll()
            remoteFolderID = 0
            remoteFolderName = "Put.io root"
            try persist()
            diskUsage = account.disk
            trashSummary = try? await putIOClient.fetchTrash()
            putIOStatus = "Connected as \(account.username)"
        } catch {
            if putIOClient is UnconfiguredPutIOClient {
                putIOStatus = "Not connected yet"
            } else {
                putIOStatus = "Put.io error · \(error.localizedDescription)"
            }
        }
    }

    /// Reads Put.io's activity feed since the last event we handled and mirrors
    /// it into History, so "what happened on Put.io" is answerable from Cargo.
    private func processPutIOEvents() async throws -> [PutIOEvent] {
        let events = try await putIOClient.fetchEvents()
        let newest = events.map(\.id).max()
        guard let lastSeen = state.lastPutIOEventID else {
            // First run: take the feed as the baseline, don't replay history.
            state.lastPutIOEventID = newest
            return []
        }
        let fresh = events.filter { $0.id > lastSeen }.sorted { $0.id < $1.id }
        for event in fresh {
            switch event.kind {
            case .transferCompleted:
                recordHistory(kind: .info, title: "Put.io finished a transfer", detail: event.name)
            case .transferError:
                recordHistory(kind: .warning, title: "Put.io transfer failed", detail: event.name)
            case .other:
                break
            }
        }
        if let newest { state.lastPutIOEventID = max(lastSeen, newest) }
        return fresh
    }

    /// Asks Put.io to unpack archives it has not been asked about yet, and
    /// clears archives whose extraction finished (their videos are now files).
    private func reconcileArchives(summary: inout CargoBackgroundCycleSummary) async {
        guard state.settings.automaticExtractEnabled else { return }
        let pending = state.remoteArchiveFiles.filter { !state.requestedExtractionFileIDs.contains($0.id) }
        if !pending.isEmpty {
            do {
                try await putIOClient.extractFiles(ids: pending.map(\.id))
                state.requestedExtractionFileIDs.append(contentsOf: pending.map(\.id))
                summary.extracting = pending.map(\.displayPath)
                recordHistory(
                    kind: .info,
                    title: "Asked Put.io to extract",
                    detail: pending.map(\.displayPath).joined(separator: ", ")
                )
            } catch {
                recordHistory(kind: .warning, title: "Put.io extraction request failed", detail: error.localizedDescription)
            }
        }
        guard !state.requestedExtractionFileIDs.isEmpty, let extractions = try? await putIOClient.fetchExtractions() else { return }
        for archive in state.remoteArchiveFiles where state.requestedExtractionFileIDs.contains(archive.id) {
            guard let extraction = extractions.last(where: { $0.name == archive.name }) else { continue }
            switch extraction.status {
            case .completed:
                state.requestedExtractionFileIDs.removeAll { $0 == archive.id }
                if state.settings.automaticRemoteCleanupEnabled {
                    do {
                        try await putIOClient.deleteFile(fileID: archive.id, skipTrash: true)
                        state.remoteArchiveFiles.removeAll { $0.id == archive.id }
                        recordHistory(kind: .success, title: "Extracted and removed archive", detail: archive.displayPath)
                    } catch {
                        recordHistory(kind: .warning, title: "Could not remove extracted archive", detail: "\(archive.displayPath): \(error.localizedDescription)")
                    }
                } else {
                    recordHistory(kind: .success, title: "Put.io extracted", detail: archive.displayPath)
                }
            case .error:
                state.requestedExtractionFileIDs.removeAll { $0 == archive.id }
                let detail = "\(archive.displayPath): \(extraction.message ?? "Put.io could not unpack it")"
                summary.failures.append(detail)
                recordHistory(kind: .failure, title: "Extraction failed", detail: detail)
            case .inProgress, .unknown:
                break
            }
        }
        try? persist()
    }

    func requestExtraction(remoteFileID: Int) async throws {
        guard let archive = state.remoteArchiveFiles.first(where: { $0.id == remoteFileID }) else {
            throw SettingsError.remoteFileMissing
        }
        try await putIOClient.extractFiles(ids: [archive.id])
        if !state.requestedExtractionFileIDs.contains(archive.id) {
            state.requestedExtractionFileIDs.append(archive.id)
        }
        try persist()
        recordHistory(kind: .info, title: "Asked Put.io to extract", detail: "\(archive.displayPath) · manual")
    }

    // MARK: - Clearing

    func clearHistory() {
        state.history.removeAll()
        state.lastUpdated = Date()
        try? persist()
    }

    /// Routine entries older than 30 days go; warnings and failures stay 90.
    private func pruneHistory() {
        let now = Date()
        state.history.removeAll { entry in
            let age = now.timeIntervalSince(entry.date)
            switch entry.kind {
            case .info, .success: return age > 30 * 86_400
            case .warning, .failure: return age > 90 * 86_400
            }
        }
    }

    func clearFailedJobs() {
        state.localJobs.removeAll { $0.status == .failed }
        try? persist()
    }

    /// "Deleted" markers only matter while the inventory could still show the
    /// file; once Put.io no longer lists it, forget it.
    private func pruneDeletedMarkers() {
        let live = Set(state.remoteMediaFiles.map(\.id)).union(state.remoteFiles.map(\.id)).union(state.remoteArchiveFiles.map(\.id))
        state.deletedRemoteFileIDs.removeAll { !live.contains($0) }
        let liveFolders = Set(state.remoteFolders.map(\.id))
        state.deletedRemoteFolderIDs.removeAll { !liveFolders.contains($0) }
    }

    func emptyPutIOTrash() async throws {
        try await putIOClient.emptyTrash()
        trashSummary = PutIOTrashSummary(count: 0, bytes: 0)
        recordHistory(kind: .success, title: "Emptied Put.io trash", detail: "manual")
    }

    func runBackgroundCycle() async -> CargoBackgroundCycleSummary {
        var summary = CargoBackgroundCycleSummary()
        await refreshFromPutIO(force: false)
        await reconcileArchives(summary: &summary)
        pruneHistory()
        pruneDeletedMarkers()
        summary.watchlistAdded = await refreshIMDbWatchlist(force: false)

        let previousRemoteMediaFileIDs = Set(state.seenRemoteMediaFileIDs)
        let isFirstObservation = !state.remoteMediaBaselineEstablished
        let newlyDiscoveredMedia = isFirstObservation
            ? []
            : state.remoteMediaFiles.filter { !previousRemoteMediaFileIDs.contains($0.id) }
        state.seenRemoteMediaFileIDs = state.remoteMediaFiles.map(\.id).sorted()
        state.remoteMediaBaselineEstablished = true
        try? store.replace(with: state)

        if !newlyDiscoveredMedia.isEmpty {
            summary.discovered = newlyDiscoveredMedia.map(\.displayPath)
            let detail = newlyDiscoveredMedia.map(\.displayPath).joined(separator: ", ")
            recordHistory(
                kind: .info,
                title: "New Put.io media found",
                detail: "\(newlyDiscoveredMedia.count) item\(newlyDiscoveredMedia.count == 1 ? "" : "s"): \(detail)"
            )
        }

        if state.settings.automaticSyncEnabled {
            for mediaFile in newlyDiscoveredMedia {
                enqueueLocalSync(remoteFile: mediaFile)
            }
        }

        let queuedJobIDs = state.localJobs
            .filter { $0.status == .queued }
            .map(\.id)
        for jobID in queuedJobIDs {
            guard let jobBeforeDownload = state.localJobs.first(where: { $0.id == jobID }) else { continue }
            let deletedFileIDsBefore = Set(state.deletedRemoteFileIDs)
            let deletedFolderIDsBefore = Set(state.deletedRemoteFolderIDs)
            await processLocalSync(remoteFileID: jobBeforeDownload.remoteFileID)

            if !deletedFileIDsBefore.contains(jobBeforeDownload.remoteFileID),
               state.deletedRemoteFileIDs.contains(jobBeforeDownload.remoteFileID) {
                summary.deleted.append(jobBeforeDownload.name)
            }
            let newlyDeletedFolderIDs = state.deletedRemoteFolderIDs.filter {
                !deletedFolderIDsBefore.contains($0)
            }
            summary.deletedFolders.append(contentsOf: newlyDeletedFolderIDs.compactMap { folderID in
                state.remoteFolders.first(where: { $0.id == folderID })?.displayPath
            })

            guard let jobAfterDownload = state.localJobs.first(where: { $0.id == jobID }) else { continue }
            switch jobAfterDownload.status {
            case .needsReview where state.settings.automaticOrganizationEnabled:
                do {
                    _ = try organizeLocalJob(jobID: jobID)
                    summary.downloaded.append(jobAfterDownload.name)
                    summary.organized.append(jobAfterDownload.name)
                } catch {
                    let detail = "\(jobAfterDownload.name): \(error.localizedDescription)"
                    summary.failures.append(detail)
                    recordHistory(kind: .failure, title: "Automatic organization failed", detail: detail)
                }
            case .needsReview:
                summary.downloaded.append(jobAfterDownload.name)
            case .failed:
                let detail = "\(jobAfterDownload.name): \(jobAfterDownload.errorMessage ?? "Download failed.")"
                summary.failures.append(detail)
            default:
                break
            }
        }

        if state.settings.automaticTransferCleanEnabled,
           state.transfers.contains(where: { [.completed, .seeding].contains($0.status) }) {
            do {
                try await putIOClient.cleanFinishedTransfers()
                state.transfers.removeAll { $0.status == .completed || $0.status == .seeding }
                try persist()
            } catch {
                recordHistory(kind: .warning, title: "Could not clear finished transfers", detail: error.localizedDescription)
            }
        }
        return summary
    }

    private static let inventoryTypes = ["FOLDER", "VIDEO", "ARCHIVE"]

    private func fetchRemoteInventory() async throws -> (mediaFiles: [RemoteFile], folders: [RemoteFile], archives: [RemoteFile]) {
        var mediaFilesByID = [Int: RemoteFile]()
        var foldersByID = [Int: RemoteFile]()
        var archivesByID = [Int: RemoteFile]()
        var folderQueue: [(id: Int, path: String)] = []

        for file in state.remoteFiles {
            if file.isFolder {
                var folder = file
                folder.path = file.name
                foldersByID[file.id] = folder
                folderQueue.append((id: file.id, path: file.name))
            } else if file.isMediaFile {
                var mediaFile = file
                mediaFile.path = file.name
                mediaFilesByID[file.id] = mediaFile
            } else if file.isArchive {
                var archive = file
                archive.path = file.name
                archivesByID[file.id] = archive
            }
        }

        var visitedFolderIDs = Set<Int>()

        while let folder = folderQueue.popLast() {
            guard visitedFolderIDs.insert(folder.id).inserted else { continue }
            // Server-side filter: sidecars never cross the wire.
            let files = try await putIOClient.fetchFiles(parentID: folder.id, types: Self.inventoryTypes)
            for file in files {
                if file.isFolder {
                    var folderFile = file
                    folderFile.path = Self.joinRemotePath(folder.path, file.name)
                    foldersByID[file.id] = folderFile
                    folderQueue.append(
                        (id: file.id, path: Self.joinRemotePath(folder.path, file.name))
                    )
                } else if file.isMediaFile {
                    var mediaFile = file
                    mediaFile.path = Self.joinRemotePath(folder.path, file.name)
                    mediaFilesByID[file.id] = mediaFile
                } else if file.isArchive {
                    var archive = file
                    archive.path = Self.joinRemotePath(folder.path, file.name)
                    archivesByID[file.id] = archive
                }
            }
        }

        func sorted(_ files: Dictionary<Int, RemoteFile>.Values) -> [RemoteFile] {
            files.sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
        }
        return (sorted(mediaFilesByID.values), sorted(foldersByID.values), sorted(archivesByID.values))
    }

    private static func joinRemotePath(_ parent: String, _ child: String) -> String {
        parent.isEmpty ? child : "\(parent)/\(child)"
    }

    private static let watchlistTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    // MARK: - Transfers

    func addTransfer(url: String) async throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SettingsError.invalidTransferURL }
        let transfer = try await putIOClient.addTransfer(url: trimmed)
        if !state.transfers.contains(where: { $0.id == transfer.id }) {
            state.transfers.insert(transfer, at: 0)
        }
        try persist()
        recordHistory(kind: .info, title: "Added transfer", detail: transfer.name)
    }

    func cancelTransfer(id: Int) async throws {
        let name = state.transfers.first { $0.id == id }?.name ?? "Transfer \(id)"
        try await putIOClient.cancelTransfers(ids: [id])
        state.transfers.removeAll { $0.id == id }
        try persist()
        recordHistory(kind: .warning, title: "Cancelled transfer", detail: name)
    }

    func retryTransfer(id: Int) async throws {
        let name = state.transfers.first { $0.id == id }?.name ?? "Transfer \(id)"
        try await putIOClient.retryTransfer(id: id)
        recordHistory(kind: .info, title: "Retried transfer", detail: name)
        await refreshFromPutIO()
    }

    func cleanFinishedTransfers() async throws {
        try await putIOClient.cleanFinishedTransfers()
        state.transfers.removeAll { $0.status == .completed || $0.status == .seeding }
        try persist()
        recordHistory(kind: .info, title: "Cleared finished transfers", detail: "Put.io transfer list cleaned")
    }

    // MARK: - File extras

    func downloadURL(remoteFileID: Int) async throws -> URL {
        try await putIOClient.downloadURL(fileID: remoteFileID)
    }

    func fetchSubtitles(remoteFileID: Int) async throws -> [PutIOSubtitle] {
        try await putIOClient.fetchSubtitles(fileID: remoteFileID)
    }

    /// Saves a Put.io subtitle next to the local copy of the file (`Name.en.srt`).
    /// Falls back to the staging folder when the file has not been downloaded yet.
    func downloadSubtitle(_ subtitle: PutIOSubtitle, remoteFileID: Int) async throws -> URL {
        guard let remoteFile = state.remoteMediaFiles.first(where: { $0.id == remoteFileID }) else {
            throw SettingsError.remoteFileMissing
        }
        let localPath = state.localJobs
            .filter { $0.remoteFileID == remoteFileID }
            .max { $0.updatedAt < $1.updatedAt }?
            .destination
        let base: URL
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            base = URL(fileURLWithPath: localPath)
        } else {
            guard let root = libraryRootURL() else { throw SettingsError.libraryRootMissing }
            base = root
                .appendingPathComponent(state.settings.stagingDirectoryName, isDirectory: true)
                .appendingPathComponent(remoteFile.name)
        }
        let language = subtitle.language.lowercased().prefix(3).replacingOccurrences(of: " ", with: "")
        let destination = base.deletingPathExtension().appendingPathExtension("\(language).srt")
        try await putIOClient.downloadSubtitle(fileID: remoteFileID, key: subtitle.key, to: destination)
        recordHistory(kind: .success, title: "Saved subtitle", detail: destination.lastPathComponent)
        return destination
    }

    func openRemoteFolder(remoteFolderID: Int) async {
        guard let folder = state.remoteFiles.first(where: { $0.id == remoteFolderID && $0.isFolder }) else {
            return
        }

        do {
            let remoteFiles = try await putIOClient.fetchFiles(parentID: folder.id, types: nil)
            remoteFolderStack.append((id: self.remoteFolderID, name: remoteFolderName))
            self.remoteFolderID = folder.id
            remoteFolderName = folder.name
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)
            try persist()
        } catch {
            putIOStatus = "Put.io error · \(error.localizedDescription)"
        }
    }

    func goBackRemoteFolder() async {
        guard let previousFolder = remoteFolderStack.popLast() else { return }

        do {
            let remoteFiles = try await putIOClient.fetchFiles(parentID: previousFolder.id, types: nil)
            remoteFolderID = previousFolder.id
            remoteFolderName = previousFolder.name
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)
            try persist()
        } catch {
            remoteFolderStack.append(previousFolder)
            putIOStatus = "Put.io error · \(error.localizedDescription)"
        }
    }

    func enqueueLocalSync(remoteFileID: Int) {
        guard let remoteFile = state.remoteFiles.first(where: { $0.id == remoteFileID })
            ?? state.remoteMediaFiles.first(where: { $0.id == remoteFileID }) else {
            return
        }
        enqueueLocalSync(remoteFile: remoteFile)
    }

    private func enqueueLocalSync(remoteFile: RemoteFile) {
        guard remoteFile.isMediaFile,
              !state.localJobs.contains(where: { $0.remoteFileID == remoteFile.id }) else {
            return
        }

        state.localJobs.append(
            LocalSyncJob(
                id: UUID(),
                remoteFileID: remoteFile.id,
                name: remoteFile.name,
                status: .queued,
                progress: 0,
                destination: state.settings.libraryRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                        .appendingPathComponent(state.settings.stagingDirectoryName, isDirectory: true)
                        .path
                },
                errorMessage: nil,
                updatedAt: Date()
            )
        )
        try? store.replace(with: state)
    }

    func processLocalSync(remoteFileID: Int) async {
        guard let jobIndex = state.localJobs.firstIndex(where: { $0.remoteFileID == remoteFileID }),
              state.localJobs[jobIndex].status == .queued,
              LibraryOrganizer.isMediaFile(named: state.localJobs[jobIndex].name) else {
            return
        }

        let jobName = state.localJobs[jobIndex].name

        guard let rootURL = libraryRootURL() else {
            updateLocalJob(
                at: jobIndex,
                status: .failed,
                progress: 0,
                destination: nil,
                errorMessage: "Choose the SSD library root in Settings first."
            )
            return
        }

        let stagingURL = rootURL.appendingPathComponent(
            state.settings.stagingDirectoryName,
            isDirectory: true
        )
        let destinationURL = stagingURL.appendingPathComponent(Self.safeFilename(jobName))

        updateLocalJob(
            at: jobIndex,
            status: .downloading,
            progress: 0,
            destination: destinationURL.path,
            errorMessage: nil
        )

        let isAccessingScopedResource = rootURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingScopedResource {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try await putIOClient.downloadFile(fileID: remoteFileID, to: destinationURL)
            try verifyLocalCopy(remoteFileID: remoteFileID, localURL: destinationURL)
            updateLocalJob(
                at: jobIndex,
                status: .needsReview,
                progress: 1,
                destination: destinationURL.path,
                errorMessage: nil
            )
            recordHistory(
                kind: .success,
                title: "Downloaded",
                detail: "\(jobName) → \(destinationURL.path)"
            )

            if state.settings.automaticRemoteCleanupEnabled {
                do {
                    _ = try await deleteRemoteFileAfterVerifiedCopy(
                        remoteFileID: remoteFileID,
                        localURL: destinationURL,
                        jobName: jobName
                    )
                } catch {
                    recordHistory(
                        kind: .failure,
                        title: "Remote cleanup failed",
                        detail: "\(jobName): \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            updateLocalJob(
                at: jobIndex,
                status: .failed,
                progress: 0,
                destination: destinationURL.path,
                errorMessage: error.localizedDescription
            )
            recordHistory(
                kind: .failure,
                title: "Download failed",
                detail: "\(jobName): \(error.localizedDescription)"
            )
        }
    }

    private func verifyLocalCopy(remoteFileID: Int, localURL: URL) throws {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw SettingsError.localCopyMissing
        }

        guard let remoteFile = state.remoteMediaFiles.first(where: { $0.id == remoteFileID })
            ?? state.remoteFiles.first(where: { $0.id == remoteFileID }) else {
            throw SettingsError.remoteFileMissing
        }

        guard remoteFile.sizeBytes <= 0 else {
            let localSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber
            guard localSize?.int64Value == remoteFile.sizeBytes else {
                throw SettingsError.localCopySizeMismatch
            }
            return
        }
    }

    /// User-initiated deletion from the Files page. No local-copy verification —
    /// the UI is responsible for confirming with the user first.
    @discardableResult
    /// Manual deletes go to Put.io's trash (recoverable). Cargo's own cleanup
    /// after a verified local copy skips the trash — otherwise the quota is
    /// only freed when someone remembers to empty it.
    func deleteRemoteFile(remoteFileID: Int, reason: String? = nil, skipTrash: Bool = false) async throws -> RemoteFile {
        guard let remoteFile = state.remoteMediaFiles.first(where: { $0.id == remoteFileID })
            ?? state.remoteFiles.first(where: { $0.id == remoteFileID }) else {
            throw SettingsError.remoteFileMissing
        }

        try await putIOClient.deleteFile(fileID: remoteFileID, skipTrash: skipTrash)
        state.remoteFiles.removeAll { $0.id == remoteFileID }
        state.remoteMediaFiles.removeAll { $0.id == remoteFileID || $0.parentID == remoteFileID }
        state.remoteFolders.removeAll { $0.id == remoteFileID }
        if !state.deletedRemoteFileIDs.contains(remoteFileID) {
            state.deletedRemoteFileIDs.append(remoteFileID)
        }
        try persist()
        recordHistory(
            kind: .success,
            title: remoteFile.isFolder ? "Deleted Put.io folder" : "Deleted from Put.io",
            detail: reason ?? "\(remoteFile.displayPath) · manual"
        )
        return remoteFile
    }

    private func deleteRemoteFileAfterVerifiedCopy(
        remoteFileID: Int,
        localURL: URL,
        jobName: String
    ) async throws -> [Int] {
        try verifyLocalCopy(remoteFileID: remoteFileID, localURL: localURL)
        let remoteFile = try await deleteRemoteFile(
            remoteFileID: remoteFileID,
            reason: "\(jobName) · local copy verified",
            skipTrash: true
        )
        do {
            return try await deleteEmptyRemoteFolders(startingAt: remoteFile.parentID)
        } catch {
            recordHistory(
                kind: .warning,
                title: "Put.io folder cleanup deferred",
                detail: "\(jobName): \(error.localizedDescription)"
            )
            return []
        }
    }

    private func deleteEmptyRemoteFolders(startingAt parentID: Int) async throws -> [Int] {
        var folderID = parentID
        var deletedFolderIDs: [Int] = []

        while folderID != 0,
              let folder = state.remoteFolders.first(where: { $0.id == folderID }) {
            let children = try await putIOClient.fetchFiles(parentID: folder.id, types: nil)
            guard children.isEmpty else { break }

            try await putIOClient.deleteFile(fileID: folder.id, skipTrash: true)
            if !state.deletedRemoteFolderIDs.contains(folder.id) {
                state.deletedRemoteFolderIDs.append(folder.id)
            }
            deletedFolderIDs.append(folder.id)
            try persist()
            recordHistory(
                kind: .success,
                title: "Deleted empty Put.io folder",
                detail: folder.displayPath
            )
            folderID = folder.parentID
        }

        return deletedFolderIDs
    }

    @discardableResult
    func organizeLocalJob(jobID: UUID) throws -> URL {
        guard let jobIndex = state.localJobs.firstIndex(where: { $0.id == jobID }),
              state.localJobs[jobIndex].status == .needsReview,
              let sourcePath = state.localJobs[jobIndex].destination else {
            throw SettingsError.inboxFileMissing
        }

        let job = state.localJobs[jobIndex]
        let preview = LibraryOrganizer.preview(for: job.name, settings: state.settings)
        guard let relativePath = preview.relativePath else {
            throw SettingsError.ambiguousMedia
        }
        guard let rootURL = libraryRootURL() else {
            throw SettingsError.inboxFileMissing
        }

        let isAccessingScopedResource = rootURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingScopedResource {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SettingsError.inboxFileMissing
        }

        let destinationURL = rootURL.appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw SettingsError.destinationAlreadyExists
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw SettingsError.unableToCreateDestination
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw SettingsError.unableToMoveFile
        }
        removeEmptyInboxFolders(afterMoving: sourceURL, rootURL: rootURL)

        state.localJobs[jobIndex].status = .completed
        state.localJobs[jobIndex].progress = 1
        state.localJobs[jobIndex].destination = destinationURL.path
        state.localJobs[jobIndex].errorMessage = nil
        state.localJobs[jobIndex].updatedAt = Date()
        try persist()
        recordHistory(
            kind: .success,
            title: "Organized",
            detail: "\(job.name) → \(destinationURL.path)"
        )
        return destinationURL
    }

    @discardableResult
    func organizeInboxFile(at sourceURL: URL) throws -> URL {
        guard let rootURL = libraryRootURL() else {
            throw SettingsError.inboxFileMissing
        }

        let inboxURL = rootURL.appendingPathComponent(
            state.settings.stagingDirectoryName,
            isDirectory: true
        ).standardizedFileURL
        let normalizedSourceURL = sourceURL.standardizedFileURL
        let inboxPrefix = inboxURL.path.hasSuffix("/") ? inboxURL.path : inboxURL.path + "/"
        guard normalizedSourceURL.path.hasPrefix(inboxPrefix),
              FileManager.default.fileExists(atPath: normalizedSourceURL.path) else {
            throw SettingsError.inboxFileMissing
        }

        let preview = LibraryOrganizer.preview(
            for: normalizedSourceURL.lastPathComponent,
            settings: state.settings
        )
        guard let relativePath = preview.relativePath else {
            throw SettingsError.ambiguousMedia
        }

        let isAccessingScopedResource = rootURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingScopedResource {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = rootURL.appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw SettingsError.destinationAlreadyExists
        }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: normalizedSourceURL, to: destinationURL)
        } catch {
            throw SettingsError.unableToMoveFile
        }
        removeEmptyInboxFolders(afterMoving: normalizedSourceURL, rootURL: rootURL)
        recordHistory(
            kind: .success,
            title: "Organized",
            detail: "\(normalizedSourceURL.lastPathComponent) → \(destinationURL.path)"
        )
        return destinationURL
    }

    private func removeEmptyInboxFolders(afterMoving sourceURL: URL, rootURL: URL) {
        let inboxURL = rootURL.appendingPathComponent(
            state.settings.stagingDirectoryName,
            isDirectory: true
        ).standardizedFileURL
        let inboxPrefix = inboxURL.path.hasSuffix("/") ? inboxURL.path : inboxURL.path + "/"
        var folderURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let fileManager = FileManager.default

        while folderURL != inboxURL && folderURL.path.hasPrefix(inboxPrefix) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: []
            ) else {
                break
            }

            let directoryPaths = Set(children.compactMap { child -> String? in
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    return nil
                }
                return child.path
            })
            let mediaFiles = children.filter {
                !directoryPaths.contains($0.path) && LibraryOrganizer.isMediaFile(named: $0.lastPathComponent)
            }

            if state.settings.automaticInboxCleanupEnabled {
                // Once a processed folder has no media or subfolders left, all other
                // files in it are sidecars/cruft and can be removed with the folder.
                guard directoryPaths.isEmpty, mediaFiles.isEmpty else { break }
                children
                    .filter { !directoryPaths.contains($0.path) }
                    .forEach { try? fileManager.removeItem(at: $0) }
            } else {
                let metadata = children.filter { $0.lastPathComponent == ".DS_Store" }
                let meaningfulChildren = children.filter { $0.lastPathComponent != ".DS_Store" }
                guard meaningfulChildren.isEmpty else { break }
                metadata.forEach { try? fileManager.removeItem(at: $0) }
            }

            guard let remaining = try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: []
            ), remaining.isEmpty else {
                break
            }
            try? fileManager.removeItem(at: folderURL)
            guard !fileManager.fileExists(atPath: folderURL.path) else { break }
            folderURL = folderURL.deletingLastPathComponent()
        }
    }

    private func updateLocalJob(
        at index: Int,
        status: LocalSyncStatus,
        progress: Double,
        destination: String?,
        errorMessage: String?
    ) {
        guard state.localJobs.indices.contains(index) else { return }
        state.localJobs[index].status = status
        state.localJobs[index].progress = progress
        state.localJobs[index].destination = destination
        state.localJobs[index].errorMessage = errorMessage
        state.localJobs[index].updatedAt = Date()
        try? store.replace(with: state)
    }

    private static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled-download" : cleaned
    }

    private func recordHistory(kind: CargoHistoryKind, title: String, detail: String) {
        state.history.insert(
            CargoHistoryEntry(
                id: UUID(),
                date: Date(),
                kind: kind,
                title: title,
                detail: detail
            ),
            at: 0
        )
        state.history = Array(state.history.prefix(200))
        state.lastUpdated = Date()
        try? store.replace(with: state)
    }

    private static func managedRemoteFiles(_ files: [RemoteFile]) -> [RemoteFile] {
        files.filter { $0.isFolder || $0.isMediaFile || $0.isArchive }
    }

}
