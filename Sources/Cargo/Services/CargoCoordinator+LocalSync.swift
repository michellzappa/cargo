import Foundation

// Download to _Inbox, verify, delete remote, organize.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    func enqueueLocalSync(remoteFileID: Int) {
        guard let remoteFile = state.remoteFiles.first(where: { $0.id == remoteFileID })
            ?? state.remoteMediaFiles.first(where: { $0.id == remoteFileID }) else {
            return
        }
        enqueueLocalSync(remoteFile: remoteFile)
    }

    func enqueueLocalSync(remoteFile: RemoteFile) {
        guard remoteFile.isMediaFile else {
            return
        }

        if let existingIndex = state.localJobs.firstIndex(where: { $0.remoteFileID == remoteFile.id }) {
            // A failed local job is retryable. Keep completed, in-flight and
            // needs-review jobs idempotent so a repeated refresh cannot start
            // a second copy of the same file.
            guard state.localJobs[existingIndex].status == .failed else { return }
            state.localJobs[existingIndex].status = .queued
            state.localJobs[existingIndex].progress = 0
            state.localJobs[existingIndex].destination = state.settings.libraryRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
                    .appendingPathComponent(state.settings.stagingDirectoryName, isDirectory: true)
                    .appendingPathComponent(Self.safeFilename(remoteFile.name))
                    .path
            }
            state.localJobs[existingIndex].errorMessage = nil
            state.localJobs[existingIndex].attempts = 0
            state.localJobs[existingIndex].updatedAt = Date()
            persistQuietly()
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
        persistQuietly()
    }

    func processLocalSync(remoteFileID: Int) async {
        guard let jobIndex = state.localJobs.firstIndex(where: { $0.remoteFileID == remoteFileID }),
              state.localJobs[jobIndex].status == .queued,
              LibraryOrganizer.isMediaFile(named: state.localJobs[jobIndex].name) else {
            return
        }

        let jobName = state.localJobs[jobIndex].name

        guard let rootURL = libraryRootURL() else {
            let message: String
            if let path = state.settings.libraryRootPath {
                let location = FileManager.default.fileExists(atPath: path) ? "The folder is present" : "The folder is not currently mounted"
                message = "Saved SSD access bookmark could not be resolved for \(path). \(location). Re-select the library root in Settings, then tap Retry."
            } else {
                message = "No SSD library root is configured. Choose the library root in Settings, then tap Retry."
            }
            updateLocalJob(
                at: jobIndex,
                status: .failed,
                progress: 0,
                destination: nil,
                errorMessage: message
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
            let jobID = state.localJobs[jobIndex].id
            try await putIOClient.downloadFile(fileID: remoteFileID, to: destinationURL) { [weak self] received, total in
                let fraction = total.map { $0 > 0 ? Double(received) / Double($0) : 0 } ?? 0
                Task { @MainActor [weak self] in
                    guard let self, let index = state.localJobs.firstIndex(where: { $0.id == jobID }),
                          state.localJobs[index].status == .downloading else { return }
                    state.localJobs[index].progress = min(max(fraction, 0), 0.999)
                    state.localJobs[index].updatedAt = Date()
                    scheduleChangeNotification()
                }
            }
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
            if state.settings.automaticSubtitlesEnabled {
                await parkPutIOSubtitle(remoteFileID: remoteFileID)
            }

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
            // A partial file on disk means the transfer broke, not the job:
            // queue it again and let the next cycle resume from the .part.
            let attempts = (state.localJobs.indices.contains(jobIndex) ? state.localJobs[jobIndex].attempts : 0) + 1
            let partialExists = FileManager.default.fileExists(atPath: PutIOAPIClient.partialURL(for: destinationURL).path)
            let willResume = partialExists && attempts < Self.maximumDownloadAttempts
            if state.localJobs.indices.contains(jobIndex) { state.localJobs[jobIndex].attempts = attempts }
            updateLocalJob(
                at: jobIndex,
                status: willResume ? .queued : .failed,
                progress: willResume ? (state.localJobs[jobIndex].progress) : 0,
                destination: destinationURL.path,
                errorMessage: willResume ? "Interrupted · resumes next cycle (attempt \(attempts))" : error.localizedDescription
            )
            recordHistory(
                kind: willResume ? .warning : .failure,
                title: willResume ? "Download interrupted" : "Download failed",
                detail: "\(jobName): \(error.localizedDescription)"
            )
        }
    }

    static let maximumDownloadAttempts = 8

    func verifyLocalCopy(remoteFileID: Int, localURL: URL) throws {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw SettingsError.localCopyMissing
        }

        guard let remoteFile = state.remoteMediaFiles.first(where: { $0.id == remoteFileID })
            ?? state.remoteFiles.first(where: { $0.id == remoteFileID }) else {
            throw SettingsError.remoteFileMissing
        }

        // Verification is the only thing standing between a download and a
        // trash-skipping remote delete, so an unknown remote size must fail
        // rather than pass by default.
        guard remoteFile.sizeBytes > 0 else {
            throw SettingsError.remoteSizeUnknown
        }
        let localSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber
        guard localSize?.int64Value == remoteFile.sizeBytes else {
            throw SettingsError.localCopySizeMismatch
        }
    }

    /// User-initiated deletion from the Files page. No local-copy verification —
    /// the UI is responsible for confirming with the user first.
    @discardableResult
    /// Manual deletes go to Put.io's trash (recoverable). Cargo's own cleanup
    /// after a verified local copy skips the trash — otherwise the quota is
    /// only freed when someone remembers to empty it.
    func deleteRemoteFile(remoteFileID: Int, reason: String? = nil, skipTrash: Bool = false) async throws -> RemoteFile {
        if isRemoteClientMode {
            let remoteState = dashboardState
            guard let file = remoteState.remoteFiles.first(where: { $0.id == remoteFileID }) else {
                throw SettingsError.remoteFileMissing
            }
            _ = try await remoteClientSession.execute(.deleteRemoteFile(remoteFileID: remoteFileID))
            return file
        }
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

    func deleteRemoteFileAfterVerifiedCopy(
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

    func deleteEmptyRemoteFolders(startingAt parentID: Int) async throws -> [Int] {
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
        if state.settings.automaticSubtitlesEnabled {
            Task { await self.attachSubtitle(to: destinationURL, remoteFileID: job.remoteFileID) }
        }
        return destinationURL
    }
}
