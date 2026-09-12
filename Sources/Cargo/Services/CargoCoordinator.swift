import Foundation

struct CargoBackgroundCycleSummary: Sendable {
    var discovered: [String] = []
    var watchlistAdded: [String] = []
    var downloaded: [String] = []
    var organized: [String] = []
    var failures: [String] = []

    var hasMeaningfulChanges: Bool {
        !discovered.isEmpty || !watchlistAdded.isEmpty || !downloaded.isEmpty || !organized.isEmpty || !failures.isEmpty
    }
}

@MainActor
final class CargoCoordinator {
    enum SettingsError: LocalizedError {
        case emptyDirectoryName
        case invalidIMDbWatchlistURL
        case inboxFileMissing
        case ambiguousMedia
        case destinationAlreadyExists
        case unableToCreateDestination
        case unableToMoveFile

        var errorDescription: String? {
            switch self {
            case .emptyDirectoryName:
                "Library folder names cannot be empty."
            case .invalidIMDbWatchlistURL:
                "Enter a public IMDb Watchlist URL."
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
    private(set) var state: CargoState
    private(set) var putIOStatus = "Not connected yet"
    private(set) var imdbWatchlistStatus = "Not synced yet"
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
        state.lastUpdated = Date()
        try store.replace(with: state)
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
        state.lastUpdated = Date()
        try store.replace(with: state)
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
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            state.imdbWatchlistLastUpdated = Date()
            state.lastUpdated = Date()
            try store.replace(with: state)
            imdbWatchlistStatus = "Updated (Self.timeFormatter.string(from: Date())) · \(items.count) titles"

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
        launchAtLogin: Bool
    ) throws {
        try LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        state.settings.automaticSyncEnabled = automaticSync
        state.settings.automaticOrganizationEnabled = automaticOrganization
        state.settings.notificationsEnabled = notifications
        state.settings.launchAtLoginEnabled = launchAtLogin
        state.lastUpdated = Date()
        try store.replace(with: state)
    }

    func clearLibraryRoot() throws {
        state.settings.libraryRootBookmark = nil
        state.settings.libraryRootPath = nil
        state.lastUpdated = Date()
        try store.replace(with: state)
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

    func refreshFromPutIO() async {
        do {
            let account = try await putIOClient.fetchAccount()
            let transfers = try await putIOClient.fetchTransfers()
            let remoteFiles = try await putIOClient.fetchFiles(parentID: 0)
            state.transfers = transfers
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)
            state.remoteMediaFiles = try await fetchAllRemoteMediaFiles()
            remoteFolderStack.removeAll()
            remoteFolderID = 0
            remoteFolderName = "Put.io root"
            state.lastUpdated = Date()
            try store.replace(with: state)
            putIOStatus = "Connected as \(account.username)"
        } catch {
            if putIOClient is UnconfiguredPutIOClient {
                putIOStatus = "Not connected yet"
            } else {
                putIOStatus = "Put.io error · \(error.localizedDescription)"
            }
        }
    }

    func runBackgroundCycle() async -> CargoBackgroundCycleSummary {
        var summary = CargoBackgroundCycleSummary()
        await refreshFromPutIO()
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
            await processLocalSync(remoteFileID: jobBeforeDownload.remoteFileID)

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

        return summary
    }

    private func fetchAllRemoteMediaFiles() async throws -> [RemoteFile] {
        var mediaFilesByID = [Int: RemoteFile]()
        var folderQueue: [(id: Int, path: String)] = []

        for file in state.remoteFiles {
            if file.isFolder {
                folderQueue.append((id: file.id, path: file.name))
            } else if file.isMediaFile {
                var mediaFile = file
                mediaFile.path = file.name
                mediaFilesByID[file.id] = mediaFile
            }
        }

        var visitedFolderIDs = Set<Int>()

        while let folder = folderQueue.popLast() {
            guard visitedFolderIDs.insert(folder.id).inserted else { continue }
            let files = try await putIOClient.fetchFiles(parentID: folder.id)
            for file in files {
                if file.isFolder {
                    folderQueue.append(
                        (id: file.id, path: Self.joinRemotePath(folder.path, file.name))
                    )
                } else if file.isMediaFile {
                    var mediaFile = file
                    mediaFile.path = Self.joinRemotePath(folder.path, file.name)
                    mediaFilesByID[file.id] = mediaFile
                }
            }
        }

        return mediaFilesByID.values.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private static func joinRemotePath(_ parent: String, _ child: String) -> String {
        parent.isEmpty ? child : "\(parent)/\(child)"
    }

    func openRemoteFolder(remoteFolderID: Int) async {
        guard let folder = state.remoteFiles.first(where: { $0.id == remoteFolderID && $0.isFolder }) else {
            return
        }

        do {
            let remoteFiles = try await putIOClient.fetchFiles(parentID: folder.id)
            remoteFolderStack.append((id: self.remoteFolderID, name: remoteFolderName))
            self.remoteFolderID = folder.id
            remoteFolderName = folder.name
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)
            state.lastUpdated = Date()
            try store.replace(with: state)
        } catch {
            putIOStatus = "Put.io error · \(error.localizedDescription)"
        }
    }

    func goBackRemoteFolder() async {
        guard let previousFolder = remoteFolderStack.popLast() else { return }

        do {
            let remoteFiles = try await putIOClient.fetchFiles(parentID: previousFolder.id)
            remoteFolderID = previousFolder.id
            remoteFolderName = previousFolder.name
            state.remoteFiles = Self.managedRemoteFiles(remoteFiles)
            state.lastUpdated = Date()
            try store.replace(with: state)
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
        state.lastUpdated = Date()
        try store.replace(with: state)
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

            let metadata = children.filter { $0.lastPathComponent == ".DS_Store" }
            let meaningfulChildren = children.filter { $0.lastPathComponent != ".DS_Store" }
            guard meaningfulChildren.isEmpty else { break }
            metadata.forEach { try? fileManager.removeItem(at: $0) }

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
        files.filter { $0.isFolder || $0.isMediaFile }
    }

}
