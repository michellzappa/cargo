import EasySubsKit
import Foundation

// Subtitles and Inbox organization.
// Stored state lives in CargoCoordinator.swift; this file holds the behaviour
// for one concern so the core file stays readable.
extension CargoCoordinator {
    // MARK: - Subtitles

    var openSubtitlesCredentials: OpenSubtitlesCredentials {
        OpenSubtitlesCredentials(
            apiKey: state.settings.openSubtitlesAPIKey,
            username: state.settings.openSubtitlesUsername,
            password: keychain.readOpenSubtitlesPassword() ?? ""
        )
    }

    func saveOpenSubtitlesPassword(_ password: String) throws {
        try keychain.saveOpenSubtitlesPassword(password)
        scheduleChangeNotification()
    }

    /// Put.io's subtitle for the file in the wanted language, kept aside until the
    /// file has its final name. Best effort; the remote copy is about to go.
    func parkPutIOSubtitle(remoteFileID: Int) async {
        guard let list = try? await putIOClient.fetchSubtitles(fileID: remoteFileID), !list.isEmpty else { return }
        let wanted = state.settings.subtitleLanguage.lowercased()
        let pick = list.first { $0.language.lowercased().hasPrefix(wanted) || $0.key.lowercased().contains(wanted) } ?? list.first!
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("cargo-\(remoteFileID).srt")
        do {
            try await putIOClient.downloadSubtitle(fileID: remoteFileID, key: pick.key, to: temporary)
            try subtitles.park(putIOSubtitle: Data(contentsOf: temporary), remoteFileID: remoteFileID)
            try? FileManager.default.removeItem(at: temporary)
        } catch {
            recordHistory(kind: .warning, title: "Put.io subtitle not saved", detail: error.localizedDescription)
        }
    }

    /// Parked Put.io subtitle if there is one, else OpenSubtitles. Records the outcome.
    @discardableResult
    func attachSubtitle(to video: URL, remoteFileID: Int?, force: Bool = false) async -> SubtitleService.Outcome {
        if !force, SubtitleService.hasSubtitle(video) { return .alreadyPresent }
        if let remoteFileID, let saved = subtitles.claimParked(remoteFileID: remoteFileID, for: video) {
            recordHistory(kind: .success, title: "Subtitle from Put.io", detail: saved.lastPathComponent)
            return .saved(saved, source: "Put.io")
        }
        if force { try? FileManager.default.removeItem(at: SubtitleService.sidecarURL(for: video)) }
        let outcome = await subtitles.fetchFromOpenSubtitles(
            for: video,
            language: state.settings.subtitleLanguage,
            credentials: openSubtitlesCredentials
        )
        switch outcome {
        case .saved(let url, let source):
            recordHistory(kind: .success, title: "Subtitle saved", detail: "\(url.lastPathComponent) · \(source)")
        case .notFound(let reason):
            recordHistory(kind: .warning, title: "No subtitle", detail: "\(video.lastPathComponent): \(reason)")
        case .noCredentials, .alreadyPresent:
            break
        }
        return outcome
    }

    /// Every video under a library item that has no subtitle yet.
    func fetchSubtitles(for item: LibraryItem) async -> (saved: Int, failed: Int) {
        guard let root = libraryRootURL() else { return (0, 0) }
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let url = root.appendingPathComponent(item.relativePath)
        var videos: [URL] = []
        if item.kind == .movie {
            videos = [url]
        } else if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            videos = enumerator.allObjects.compactMap { $0 as? URL }.filter { LibraryOrganizer.isMediaFile(named: $0.lastPathComponent) }
        }
        var saved = 0, failed = 0
        for video in videos where !SubtitleService.hasSubtitle(video) {
            if case .saved = await attachSubtitle(to: video, remoteFileID: nil) { saved += 1 } else { failed += 1 }
        }
        return (saved, failed)
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

    func removeEmptyInboxFolders(afterMoving sourceURL: URL, rootURL: URL) {
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
}
