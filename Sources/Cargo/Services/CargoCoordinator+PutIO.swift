import Foundation

// Put.io transfers, file extras, folder navigation.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    // MARK: - Transfers

    func addTransfer(url: String) async throws {
        if try await executeRemoteIfNeeded(.addTransfer(url: url)) { return }
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
        if try await executeRemoteIfNeeded(.cancelTransfer(id: id)) { return }
        let name = state.transfers.first { $0.id == id }?.name ?? "Transfer \(id)"
        try await putIOClient.cancelTransfers(ids: [id])
        state.transfers.removeAll { $0.id == id }
        try persist()
        recordHistory(kind: .warning, title: "Cancelled transfer", detail: name)
    }

    func retryTransfer(id: Int) async throws {
        if try await executeRemoteIfNeeded(.retryTransfer(id: id)) { return }
        let name = state.transfers.first { $0.id == id }?.name ?? "Transfer \(id)"
        try await putIOClient.retryTransfer(id: id)
        recordHistory(kind: .info, title: "Retried transfer", detail: name)
        await refreshFromPutIO()
    }

    func cleanFinishedTransfers() async throws {
        if try await executeRemoteIfNeeded(.cleanFinishedTransfers) { return }
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
        if (try? await executeRemoteIfNeeded(.openRemoteFolder(remoteFolderID: remoteFolderID))) == true { return }
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
        if (try? await executeRemoteIfNeeded(.goBackRemoteFolder)) == true { return }
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
}
