import Foundation

/// What is actually on the SSD, read from the folder layout the organizer
/// writes: `Movies/Title (Year).ext` and `TV Shows/Title (Year)/Season NN/… - SxxEyy.ext`.
/// The disk is the source of truth; nothing here depends on sync history.
struct LibraryItem: Codable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case movie, show }

    /// Stable across rescans: `movie:Title (Year)` / `show:Title (Year)`.
    let id: String
    let kind: Kind
    var title: String
    var year: Int?
    /// Relative to the library root.
    var relativePath: String
    var sizeBytes: Int64
    var addedAt: Date
    /// Season number → episode numbers present. Empty for movies.
    var episodes: [Int: [Int]]

    var displayTitle: String { year.map { "\(title) (\($0))" } ?? title }
    var episodeCount: Int { episodes.values.reduce(0) { $0 + $1.count } }
    var seasonCount: Int { episodes.count }
}

enum LibraryIndex {
    private static let videoExtensions: Set<String> = ["avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ts", "webm", "wmv"]

    static func scan(root: URL, settings: CargoSettings) -> [LibraryItem] {
        var items: [LibraryItem] = []
        let fileManager = FileManager.default
        // The enumerator hands back resolved paths (/private/var…); compare like with like.
        let rootPath = root.resolvingSymlinksInPath().path
        func relative(_ url: URL) -> String {
            let path = url.resolvingSymlinksInPath().path
            return path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
        }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey]

        // Movies: one file per movie, straight under the folder (subfolders tolerated).
        let moviesURL = root.appendingPathComponent(settings.moviesDirectoryName, isDirectory: true)
        if let enumerator = fileManager.enumerator(at: moviesURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where videoExtensions.contains(url.pathExtension.lowercased()) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let (title, year) = titleAndYear(from: url.deletingPathExtension().lastPathComponent)
                items.append(LibraryItem(
                    id: "movie:\(title)\(year.map { " (\($0))" } ?? "")",
                    kind: .movie,
                    title: title,
                    year: year,
                    relativePath: relative(url),
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    addedAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
                    episodes: [:]
                ))
            }
        }

        // Shows: folder per show, folder per season, file per episode.
        let showsURL = root.appendingPathComponent(settings.tvShowsDirectoryName, isDirectory: true)
        let showFolders = (try? fileManager.contentsOfDirectory(at: showsURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        for showURL in showFolders where (try? showURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let (title, year) = titleAndYear(from: showURL.lastPathComponent)
            var episodes: [Int: [Int]] = [:]
            var size: Int64 = 0
            var newest = Date.distantPast
            if let enumerator = fileManager.enumerator(at: showURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where videoExtensions.contains(url.pathExtension.lowercased()) {
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    size += Int64(values?.fileSize ?? 0)
                    newest = max(newest, values?.creationDate ?? values?.contentModificationDate ?? .distantPast)
                    if let (season, episode) = seasonEpisode(from: url.lastPathComponent) {
                        episodes[season, default: []].append(episode)
                    }
                }
            }
            for key in episodes.keys { episodes[key] = Array(Set(episodes[key]!)).sorted() }
            guard !episodes.isEmpty else { continue }
            items.append(LibraryItem(
                id: "show:\(title)\(year.map { " (\($0))" } ?? "")",
                kind: .show,
                title: title,
                year: year,
                relativePath: relative(showURL),
                sizeBytes: size,
                addedAt: newest,
                episodes: episodes
            ))
        }
        return items.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    /// "Arrival (2016)" → ("Arrival", 2016); "Arrival" → ("Arrival", nil).
    static func titleAndYear(from name: String) -> (String, Int?) {
        let pattern = #"^(.*?)\s*\((\d{4})\)\s*$"#
        if let match = name.range(of: pattern, options: .regularExpression),
           let regex = try? NSRegularExpression(pattern: pattern),
           let result = regex.firstMatch(in: name, range: NSRange(match, in: name)),
           let titleRange = Range(result.range(at: 1), in: name),
           let yearRange = Range(result.range(at: 2), in: name) {
            return (String(name[titleRange]), Int(name[yearRange]))
        }
        return (name, nil)
    }

    static func seasonEpisode(from fileName: String) -> (Int, Int)? {
        let pattern = #"(?i)s(\d{1,2})e(\d{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
              let seasonRange = Range(result.range(at: 1), in: fileName),
              let episodeRange = Range(result.range(at: 2), in: fileName),
              let season = Int(fileName[seasonRange]), let episode = Int(fileName[episodeRange])
        else { return nil }
        return (season, episode)
    }
}
