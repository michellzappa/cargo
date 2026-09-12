import Foundation

@MainActor
final class CargoCoordinator {
    enum SettingsError: LocalizedError {
        case emptyDirectoryName
        case inboxFileMissing
        case ambiguousMedia
        case destinationAlreadyExists
        case unableToCreateDestination
        case unableToMoveFile

        var errorDescription: String? {
            switch self {
            case .emptyDirectoryName:
                "Library folder names cannot be empty."
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
    private var putIOClient: PutIOClient
    private var remoteFolderStack: [(id: Int, name: String)] = []
    private var pendingOAuthState: String?
    private(set) var state: CargoState
    private(set) var putIOStatus = "Not connected yet"
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
        return (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: keys,
            options: []
        ))?
            .filter { url in
                url.lastPathComponent != ".DS_Store" &&
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            ?? []
    }

    func refreshFromPutIO() async {
        do {
            let account = try await putIOClient.fetchAccount()
            let transfers = try await putIOClient.fetchTransfers()
            let remoteFiles = try await putIOClient.fetchFiles(parentID: 0)
            state.transfers = transfers
            state.remoteFiles = remoteFiles
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

    func openRemoteFolder(remoteFolderID: Int) async {
        guard let folder = state.remoteFiles.first(where: { $0.id == remoteFolderID && $0.isFolder }) else {
            return
        }

        do {
            let remoteFiles = try await putIOClient.fetchFiles(parentID: folder.id)
            remoteFolderStack.append((id: self.remoteFolderID, name: remoteFolderName))
            self.remoteFolderID = folder.id
            remoteFolderName = folder.name
            state.remoteFiles = remoteFiles
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
            state.remoteFiles = remoteFiles
            state.lastUpdated = Date()
            try store.replace(with: state)
        } catch {
            remoteFolderStack.append(previousFolder)
            putIOStatus = "Put.io error · \(error.localizedDescription)"
        }
    }

    func enqueueLocalSync(remoteFileID: Int) {
        guard let remoteFile = state.remoteFiles.first(where: { $0.id == remoteFileID }),
              !remoteFile.isFolder,
              !state.localJobs.contains(where: { $0.remoteFileID == remoteFileID }) else {
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
              let remoteFile = state.remoteFiles.first(where: { $0.id == remoteFileID }),
              !remoteFile.isFolder else {
            return
        }

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
        let destinationURL = stagingURL.appendingPathComponent(Self.safeFilename(remoteFile.name))

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
            try await putIOClient.downloadFile(fileID: remoteFile.id, to: destinationURL)
            updateLocalJob(
                at: jobIndex,
                status: .needsReview,
                progress: 1,
                destination: destinationURL.path,
                errorMessage: nil
            )
        } catch {
            updateLocalJob(
                at: jobIndex,
                status: .failed,
                progress: 0,
                destination: destinationURL.path,
                errorMessage: error.localizedDescription
            )
        }
    }

    func organizeLocalJob(jobID: UUID) throws {
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

        state.localJobs[jobIndex].status = .completed
        state.localJobs[jobIndex].progress = 1
        state.localJobs[jobIndex].destination = destinationURL.path
        state.localJobs[jobIndex].errorMessage = nil
        state.localJobs[jobIndex].updatedAt = Date()
        state.lastUpdated = Date()
        try store.replace(with: state)
    }

    func organizeInboxFile(at sourceURL: URL) throws {
        guard let rootURL = libraryRootURL() else {
            throw SettingsError.inboxFileMissing
        }

        let inboxURL = rootURL.appendingPathComponent(
            state.settings.stagingDirectoryName,
            isDirectory: true
        ).standardizedFileURL
        let normalizedSourceURL = sourceURL.standardizedFileURL
        guard normalizedSourceURL.deletingLastPathComponent() == inboxURL,
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

}
