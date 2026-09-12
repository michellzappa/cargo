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

    static func preview(for fileName: String, settings: CargoSettings) -> LibrarySortPreview {
        let safeName = safeFilename(fileName)

        if let episode = episodeMarker(in: safeName) {
            let showName = normalizedTitle(episode.prefix)
            guard !showName.isEmpty else {
                return LibrarySortPreview(
                    kind: .review,
                    relativePath: nil,
                    explanation: "TV episode marker found, but the show title is unclear."
                )
            }

            let seasonName = String(format: "Season %02d", episode.season)
            let relativePath = [
                settings.tvShowsDirectoryName,
                showName,
                seasonName,
                safeName
            ].joined(separator: "/")
            return LibrarySortPreview(
                kind: .tvEpisode,
                relativePath: relativePath,
                explanation: "Filename contains \(episode.marker)."
            )
        }

        let fileExtension = URL(fileURLWithPath: safeName).pathExtension.lowercased()
        guard videoExtensions.contains(fileExtension) else {
            return LibrarySortPreview(
                kind: .review,
                relativePath: nil,
                explanation: "Unsupported or ambiguous media filename."
            )
        }

        return LibrarySortPreview(
            kind: .movie,
            relativePath: "\(settings.moviesDirectoryName)/\(safeName)",
            explanation: "Video file without a TV episode marker."
        )
    }

    private static func episodeMarker(in fileName: String) -> (season: Int, marker: String, prefix: String)? {
        let expression = #"(?i)s(\d{1,2})e\d{1,3}(?:[-.]e?\d{1,3})?"#
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

    private static func normalizedTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
