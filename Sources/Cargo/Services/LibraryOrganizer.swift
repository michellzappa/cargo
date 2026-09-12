import Foundation

enum LibraryMediaKind: String, Equatable, Sendable {
    case movie
    case tvEpisode
    case review

    var displayName: String {
        switch self {
        case .movie: "Movie"
        case .tvEpisode: "TV episode"
        case .review: "Needs review"
        }
    }
}

struct LibrarySortPreview: Equatable, Sendable {
    let kind: LibraryMediaKind
    let relativePath: String?
    let explanation: String
}

enum LibraryOrganizer {
    private static let videoExtensions: Set<String> = [
        "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ts", "webm", "wmv"
    ]

    static func isMediaFile(named fileName: String) -> Bool {
        let safeName = safeFilename(fileName)
        let fileExtension = URL(fileURLWithPath: safeName).pathExtension.lowercased()
        return videoExtensions.contains(fileExtension)
    }

    static func preview(for fileName: String, settings: CargoSettings) -> LibrarySortPreview {
        let safeName = safeFilename(fileName)
        let extensionName = URL(fileURLWithPath: safeName).pathExtension.lowercased()

        guard videoExtensions.contains(extensionName) else {
            return LibrarySortPreview(
                kind: .review,
                relativePath: nil,
                explanation: "Unsupported or ambiguous media filename."
            )
        }

        if let episode = episodeMarker(in: safeName) {
            let showName = normalizedShowTitle(episode.prefix)
            guard !showName.isEmpty else {
                return LibrarySortPreview(
                    kind: .review,
                    relativePath: nil,
                    explanation: "TV episode marker found, but the show title is unclear."
                )
            }

            let seasonName = String(format: "Season %02d", episode.season)
            let renamedFile = "\(showName) - \(episode.marker)\(fileExtension(of: safeName))"
            let relativePath = [
                settings.tvShowsDirectoryName,
                showName,
                seasonName,
                renamedFile
            ].joined(separator: "/")
            return LibrarySortPreview(
                kind: .tvEpisode,
                relativePath: relativePath,
                explanation: "Filename contains \(episode.marker); release metadata will be removed."
            )
        }

        let renamedFile = cleanedMovieFilename(safeName)
        return LibrarySortPreview(
            kind: .movie,
            relativePath: "\(settings.moviesDirectoryName)/\(renamedFile)",
            explanation: "Video file without a TV episode marker; release metadata will be removed."
        )
    }

    private static func episodeMarker(in fileName: String) -> (season: Int, marker: String, prefix: String)? {
        let expression = #"(?i)s(\d{1,2})e\d{1,3}(?:[-.]e?\d{1,3})?(?=[^0-9]|$)"#
        guard let regex = try? NSRegularExpression(pattern: expression),
              let match = regex.firstMatch(
                  in: fileName,
                  range: NSRange(fileName.startIndex..., in: fileName)
              ),
              let seasonRange = Range(match.range(at: 1), in: fileName),
              let markerRange = Range(match.range, in: fileName),
              let season = Int(fileName[seasonRange]) else {
            return nil
        }

        return (
            season: season,
            marker: String(fileName[markerRange]).uppercased(),
            prefix: String(fileName[..<markerRange.lowerBound])
        )
    }

    private static func normalizedShowTitle(_ value: String) -> String {
        let cleaned = removeReleaseMetadata(from: value)
        guard let year = year(in: cleaned) else {
            return normalizedTitle(cleaned)
        }
        let titleEnd = cleaned.range(of: year)
        let title = titleEnd.map { String(cleaned[..<$0.lowerBound]) } ?? cleaned
        let normalized = normalizedTitle(title)
        return normalized.isEmpty ? "" : "\(normalized) (\(year))"
    }

    private static func cleanedMovieFilename(_ fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let cleaned = removeReleaseMetadata(from: stem)
        let title: String
        let yearText: String?
        if let year = year(in: cleaned), let yearRange = cleaned.range(of: year) {
            title = String(cleaned[..<yearRange.lowerBound])
            yearText = year
        } else {
            title = cleaned
            yearText = nil
        }

        let normalized = normalizedTitle(title)
        let finalTitle = normalized.isEmpty ? normalizedTitle(stem) : normalized
        let baseName = yearText.map { "\(finalTitle) (\($0))" } ?? finalTitle
        return baseName + fileExtension(of: fileName)
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func removeReleaseMetadata(from value: String) -> String {
        var cleaned = value
        let junkParentheses = #"(?i)\([^)]*(?:\d{3,4}p|4k|bluray|brrip|bdrip|webrip|web[- ]dl|x26[45]|h\.?26[45]|aac|eac3|dts|proper|repack|yts|timesuck)[^)]*\)"#
        cleaned = cleaned.replacingOccurrences(of: junkParentheses, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)

        let releaseMarker = #"(?i)(?:^|[ ._-])(?:2160p|1080p|720p|480p|4k|8k|bluray|blu-ray|bdrip|brrip|webrip|web[- ]dl|webdl|h\.?264|h\.?265|x264|x265|hevc|avc|aac|eac3|ac3|dts|hdr|remux|proper|repack|yts|eztv|ethel|timesuck)(?:$|[ ._\[-])"#
        if let range = cleaned.range(of: releaseMarker, options: .regularExpression) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        return cleaned
    }

    private static func year(in value: String) -> String? {
        let expression = #"(?<!\d)(?:19|20)\d{2}(?!\d)"#
        guard let range = value.range(of: expression, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    private static func fileExtension(of fileName: String) -> String {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        return fileExtension.isEmpty ? "" : ".\(fileExtension.lowercased())"
    }

    private static func safeFilename(_ value: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: value).lastPathComponent
        let cleaned = lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled-download" : cleaned
    }
}
