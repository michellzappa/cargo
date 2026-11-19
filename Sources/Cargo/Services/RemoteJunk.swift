import Foundation

/// Decides what on Put.io is not worth keeping: extras that are not the main
/// video, and release folders that hold only leftovers. Files outside these
/// rules, such as a game or a book, are never junk, and a top-level folder is
/// never removed.
enum RemoteJunk {
    struct Classification {
        /// Videos that Cargo must not download.
        var extraVideoIDs: Set<Int> = []
        /// The fewest files and folders whose removal clears all the junk.
        var removable: [RemoteFile] = []
    }

    private static let extraFolderNames: Set<String> = [
        "behind the scenes", "bonus", "deleted scenes", "extras", "featurettes",
        "interviews", "sample", "samples", "scenes", "season 00", "season 0",
        "shorts", "specials", "trailers"
    ]
    private static let leftoverExtensions: Set<String> = [
        "exe", "gif", "htm", "html", "idx", "jpeg", "jpg", "lnk", "md5", "nfo",
        "png", "sfv", "srt", "sub", "txt", "url", "website"
    ]
    /// A release's sample or trailer is small. A larger file with the word in
    /// its name is a title, such as "Trailer Park Boys".
    private static let namedExtraMaximumBytes: Int64 = 500_000_000
    /// In a movie folder, a video under this share of the largest one is an extra.
    private static let movieExtraMaximumShare = 0.25

    static func isExtraVideo(_ file: RemoteFile) -> Bool {
        let components = file.displayPath.split(separator: "/").map { $0.lowercased() }
        if components.dropLast().contains(where: extraFolderNames.contains) { return true }

        let stem = URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent.lowercased()
        if extraFolderNames.contains(stem) { return true }
        if let (season, _) = LibraryIndex.seasonEpisode(from: file.name) {
            return season == 0
        }
        if stem.range(of: #"\bscene\s+\d"#, options: .regularExpression) != nil { return true }
        return file.sizeBytes < namedExtraMaximumBytes
            && stem.range(of: #"\b(sample|trailer)\b"#, options: .regularExpression) != nil
    }

    static func isLeftover(_ file: RemoteFile) -> Bool {
        !file.isFolder && leftoverExtensions.contains(URL(fileURLWithPath: file.name).pathExtension.lowercased())
    }

    /// `children` holds the full listing of every folder in `folders`.
    static func classify(
        folders: [Int: RemoteFile],
        children: [Int: [RemoteFile]],
        mediaFiles: [RemoteFile]
    ) -> Classification {
        var extras = Set(mediaFiles.filter(isExtraVideo).map(\.id))

        // Loose files in a top-level folder are separate releases, so only a
        // nested folder counts as one movie.
        let byFolder = Dictionary(grouping: mediaFiles.filter { !extras.contains($0.id) }, by: \.parentID)
        for (folderID, videos) in byFolder where videos.count > 1 {
            guard let folder = folders[folderID], folder.parentID != 0,
                  !videos.contains(where: { LibraryIndex.seasonEpisode(from: $0.name) != nil }),
                  let largest = videos.map(\.sizeBytes).max() else { continue }
            let limit = Double(largest) * movieExtraMaximumShare
            extras.formUnion(videos.filter { Double($0.sizeBytes) < limit }.map(\.id))
        }

        func isJunkFolder(_ id: Int) -> Bool {
            guard let folder = folders[id], folder.parentID != 0, let listing = children[id] else { return false }
            return listing.allSatisfy { file in
                file.isFolder ? isJunkFolder(file.id) : extras.contains(file.id) || isLeftover(file)
            }
        }

        let junkFolders = folders.values.filter { isJunkFolder($0.id) }
        let junkFolderIDs = Set(junkFolders.map(\.id))
        let removableFolders = junkFolders.filter { !junkFolderIDs.contains($0.parentID) }
        let removableExtras = mediaFiles.filter { extras.contains($0.id) && !junkFolderIDs.contains($0.parentID) }
        let removable = (removableFolders + removableExtras).sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
        return Classification(extraVideoIDs: extras, removable: removable)
    }
}
