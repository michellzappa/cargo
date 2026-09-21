import EasySubsKit
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
        case remoteSizeUnknown
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
            case .remoteSizeUnknown:
                "Cargo did not delete the Put.io file because Put.io reported no size to verify against."
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

    let store: CargoStore
    let keychain = KeychainStore()
    let remoteClientSession = CargoRemoteClientSession()
    let remotePresenceRegistry = CargoRemotePresenceRegistry()
    let subtitles = SubtitleService()
    let imdbWatchlistService = IMDbWatchlistService()
    var putIOClient: PutIOClient
    var chillClient: ChillClient
    var remoteFolderStack: [(id: Int, name: String)] = []
    var pendingOAuthState: String?
    /// Posted on the main queue, coalesced, whenever state or status text changes.
    static let didChange = Notification.Name("CargoCoordinator.didChange")
    static let didRequestChillSearch = Notification.Name("CargoCoordinator.didRequestChillSearch")

    // Setters are module-internal so the CargoCoordinator+*.swift extensions
    // can mutate; UI code only reads these.
    var state: CargoState {
        didSet { scheduleChangeNotification() }
    }
    var putIOStatus = "Not connected yet" {
        didSet { scheduleChangeNotification() }
    }
    var chillStatus = "Not connected yet" {
        didSet { scheduleChangeNotification() }
    }
    var chillSearchQuery = ""
    var chillSearchResults: [ChillSearchResult] = [] {
        didSet { scheduleChangeNotification() }
    }
    var chillSearchStatus = "Search Chill for a release" {
        didSet { scheduleChangeNotification() }
    }
    var chillCatalogMovies: [ChillMovie] = [] {
        didSet { scheduleChangeNotification() }
    }
    var chillCatalogShows: [ChillTVShow] = [] {
        didSet { scheduleChangeNotification() }
    }
    var chillCatalogStatus = "Top movies and series appear here" {
        didSet { scheduleChangeNotification() }
    }
    var imdbWatchlistStatus = "Not synced yet" {
        didSet { scheduleChangeNotification() }
    }
    private var changeNotificationScheduled = false
    var tmdbStatus: String? {
        didSet { scheduleChangeNotification() }
    }
    var discoverMetadata: [String: TMDBMetadata] = [:]
    let discoverRatingsCache = OMDBRatingsCache()
    var diskUsage: PutIODiskUsage? {
        didSet { scheduleChangeNotification() }
    }
    /// What is sitting in Put.io's trash, refreshed with the account.
    var trashSummary: PutIOTrashSummary? {
        didSet { scheduleChangeNotification() }
    }
    var remoteFolderID = 0
    var remoteFolderName = "Put.io root"

    var canGoBackRemoteFolder: Bool {
        !remoteFolderStack.isEmpty
    }

    init(
        store: CargoStore = CargoStore(),
        client: PutIOClient? = nil,
        chillClient: ChillClient? = nil
    ) {
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
        if let chillClient {
            self.chillClient = chillClient
            self.chillStatus = "Test client"
        } else if let token = keychain.readChillToken(), !token.isEmpty {
            self.chillClient = ChillAPIClient(token: token)
            self.chillStatus = "Token saved · not tested"
        } else {
            self.chillClient = UnconfiguredChillClient()
        }
        self.state = store.snapshot()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteClientDidChange),
            name: CargoRemoteClientSession.didChange,
            object: remoteClientSession
        )
        if self.state.settings.stagingDirectoryName == ".cargo-incoming" {
            self.state.settings.stagingDirectoryName = "_Inbox"
            self.persistQuietly()
        }
        requeueInterruptedJobs()
    }

    @objc private func remoteClientDidChange() {
        scheduleChangeNotification()
    }

    /// A download in flight when the app quit is gone; the job record isn't.
    /// The cycle only picks up `queued`, so put them back — the `.part` file
    /// in `_Inbox` means they continue where they stopped.
    private func requeueInterruptedJobs() {
        var interrupted: [String] = []
        for index in state.localJobs.indices where [.downloading, .importing].contains(state.localJobs[index].status) {
            state.localJobs[index].status = .queued
            state.localJobs[index].progress = 0
            state.localJobs[index].errorMessage = nil
            state.localJobs[index].updatedAt = Date()
            interrupted.append(state.localJobs[index].name)
        }
        guard !interrupted.isEmpty else { return }
        persistQuietly()
        recordHistory(kind: .warning, title: "Resuming interrupted download\(interrupted.count == 1 ? "" : "s")", detail: interrupted.joined(separator: ", "))
    }

    func refresh() {
        state = store.snapshot()
    }

    var isConnected: Bool {
        putIOStatus.hasPrefix("Connected as ")
    }

    var isChillConnected: Bool {
        chillStatus.hasPrefix("Connected as ")
    }

    var isRemoteClientMode: Bool {
        remoteClientSession.isConnected && remoteClientSession.snapshot != nil
    }

    var dashboardState: CargoState {
        guard let snapshot = remoteClientSession.snapshot else { return state }
        return snapshot.dashboardState(preserving: state)
    }

    var dashboardIsConnected: Bool {
        remoteClientSession.snapshot?.putIO.connected ?? isConnected
    }

    var dashboardPutIOStatus: String {
        remoteClientSession.snapshot?.putIO.status ?? putIOStatus
    }

    var dashboardIsChillConnected: Bool {
        remoteClientSession.snapshot?.chill.connected ?? isChillConnected
    }

    var dashboardChillStatus: String {
        remoteClientSession.snapshot?.chill.status ?? chillStatus
    }

    // Search is per machine: a client runs it through the resident but keeps
    // the query and results to itself, so two screens never fight over one box.
    var dashboardChillSearchQuery: String { chillSearchQuery }
    var dashboardChillSearchResults: [ChillSearchResult] { chillSearchResults }
    var dashboardChillSearchStatus: String { chillSearchStatus }

    var dashboardChillCatalogMovies: [ChillMovie] {
        remoteClientSession.snapshot?.chillCatalog.movies.map(ChillMovie.init) ?? chillCatalogMovies
    }

    var dashboardChillCatalogShows: [ChillTVShow] {
        remoteClientSession.snapshot?.chillCatalog.series.map(ChillTVShow.init) ?? chillCatalogShows
    }

    var dashboardChillCatalogStatus: String {
        remoteClientSession.snapshot?.chillCatalog.status ?? chillCatalogStatus
    }

    var dashboardWatchlistStatus: String {
        remoteClientSession.snapshot?.watchlistStatus ?? imdbWatchlistStatus
    }

    /// Executes a command on the resident when this installation is acting as
    /// a client. Provider credentials and local filesystem paths stay resident-side.
    func executeRemoteCommand(_ command: CargoRemoteCommand) async throws {
        guard isRemoteClientMode else { return }
        _ = try await remoteClientSession.execute(command)
    }

    func executeRemoteIfNeeded(_ command: CargoRemoteCommand) async throws -> Bool {
        guard isRemoteClientMode else { return false }
        _ = try await remoteClientSession.execute(command)
        return true
    }

    var remoteAPITokenExists: Bool {
        guard let token = keychain.readRemoteAPIToken() else { return false }
        return !token.isEmpty
    }

    func ensureRemoteAPIToken() throws -> String {
        try keychain.ensureRemoteAPIToken()
    }

    func rotateRemoteAPIToken() throws -> String {
        let token = try keychain.rotateRemoteAPIToken()
        scheduleChangeNotification()
        return token
    }

    func persist() throws {
        state.lastUpdated = Date()
        try store.replace(with: state)
        if lastPersistError != nil {
            lastPersistError = nil
            recordHistory(kind: .info, title: "State saving recovered", detail: store.stateURL.path)
        }
    }

    /// The last error from a save that nothing was going to catch (SSD gone,
    /// disk full, permissions). Shown in the menu bar until a save succeeds.
    var lastPersistError: String? {
        didSet { if lastPersistError != oldValue { scheduleChangeNotification() } }
    }

    /// For the many fire-and-forget saves in the workflow: a failure is logged
    /// and surfaced once instead of vanishing behind `try?`.
    func persistQuietly() {
        do {
            try persist()
        } catch {
            let message = error.localizedDescription
            NSLog("Cargo could not save state: %@", message)
            if lastPersistError != message {
                lastPersistError = message
                recordHistory(kind: .warning, title: "Cargo could not save its state", detail: message, persisting: false)
            }
        }
    }

    func scheduleChangeNotification() {
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
        persistQuietly()
    }

    func requestExtraction(remoteFileID: Int) async throws {
        if try await executeRemoteIfNeeded(.requestExtraction(remoteFileID: remoteFileID)) { return }
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
        if isRemoteClientMode {
            Task { try? await remoteClientSession.execute(.clearHistory) }
            return
        }
        state.history.removeAll()
        state.lastUpdated = Date()
        persistQuietly()
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
        if isRemoteClientMode {
            Task { try? await remoteClientSession.execute(.clearFailedJobs) }
            return
        }
        state.localJobs.removeAll { $0.status == .failed }
        persistQuietly()
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
        if isRemoteClientMode {
            var summary = CargoBackgroundCycleSummary()
            do {
                _ = try await remoteClientSession.execute(.refresh)
            } catch {
                summary.failures = [error.localizedDescription]
            }
            return summary
        }
        var summary = CargoBackgroundCycleSummary()
        await refreshFromPutIO(force: false)
        await reconcileArchives(summary: &summary)
        pruneHistory()
        pruneDeletedMarkers()
        summary.watchlistAdded = await refreshIMDbWatchlist(force: false)
        scanLibrary()
        await enrichMetadata()

        let previousRemoteMediaFileIDs = Set(state.seenRemoteMediaFileIDs)
        let isFirstObservation = !state.remoteMediaBaselineEstablished
        let newlyDiscoveredMedia = isFirstObservation
            ? []
            : state.remoteMediaFiles.filter { !previousRemoteMediaFileIDs.contains($0.id) }
        state.seenRemoteMediaFileIDs = state.remoteMediaFiles.map(\.id).sorted()
        state.remoteMediaBaselineEstablished = true
        persistQuietly()

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

        scanLibrary()
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

    static func joinRemotePath(_ parent: String, _ child: String) -> String {
        parent.isEmpty ? child : "\(parent)/\(child)"
    }

    static let watchlistTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    func updateLocalJob(
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
        persistQuietly()
    }

    static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled-download" : cleaned
    }

    func recordHistory(kind: CargoHistoryKind, title: String, detail: String, persisting: Bool = true) {
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
        if persisting { persistQuietly() }
    }

    static func managedRemoteFiles(_ files: [RemoteFile]) -> [RemoteFile] {
        files.filter { $0.isFolder || $0.isMediaFile || $0.isArchive }
    }

}
