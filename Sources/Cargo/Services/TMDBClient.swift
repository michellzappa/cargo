import AppKit
import Foundation

/// The bits of TMDB Cargo uses: resolve an IMDb id, search a title, and read
/// how many episodes a season has. Free v3 API key; Infuse uses the same data,
/// so titles and years line up with the Apple TV.
struct TMDBMetadata: Codable, Sendable, Equatable {
    enum MediaType: String, Codable, Sendable { case movie, tv }
    let tmdbID: Int
    let mediaType: MediaType
    var title: String
    var year: Int?
    var posterPath: String?
    var overview: String?
    var voteAverage: Double?
    var voteCount: Int?
    var imdbID: String?
    /// Season number → episode count, for shows.
    var episodeCounts: [Int: Int]
    var fetchedAt: Date

    var posterURL: URL? { posterPath.map { URL(string: "https://image.tmdb.org/t/p/w185\($0)")! } }
    var pageURL: URL { URL(string: "https://www.themoviedb.org/\(mediaType.rawValue)/\(tmdbID)")! }
    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 7 * 86_400 }
}

struct TMDBClient: Sendable {
    enum ClientError: LocalizedError {
        case missingKey, requestFailed(String), notFound
        var errorDescription: String? {
            switch self {
            case .missingKey: "No TMDB API key. Add one in Settings → Library."
            case .requestFailed(let message): "TMDB: \(message)"
            case .notFound: "TMDB has no match."
            }
        }
    }

    let apiKey: String
    private let session = URLSession.shared
    private let base = URL(string: "https://api.themoviedb.org/3/")!

    func find(imdbID: String) async throws -> TMDBMetadata {
        let envelope: FindEnvelope = try await get("find/\(imdbID)", ["external_source": "imdb_id"])
        if let movie = envelope.movieResults.first { return try await metadata(for: movie, type: .movie) }
        if let show = envelope.tvResults.first { return try await metadata(for: show, type: .tv) }
        throw ClientError.notFound
    }

    /// Search with the year first; if that finds nothing, without it. Among the
    /// results, prefer an exact normalized title, then a year within one.
    func search(title: String, year: Int?, type: TMDBMetadata.MediaType) async throws -> TMDBMetadata {
        var results = try await searchResults(title: title, year: year, type: type)
        if results.isEmpty, year != nil { results = try await searchResults(title: title, year: nil, type: type) }
        guard !results.isEmpty else { throw ClientError.notFound }
        let wanted = Self.normalize(title)
        func score(_ result: Result) -> Int {
            var score = 0
            let names = [result.title, result.name, result.originalTitle, result.originalName].compactMap { $0 }.map(Self.normalize)
            if names.contains(wanted) { score += 4 }
            else if names.contains(where: { $0.hasPrefix(wanted) || wanted.hasPrefix($0) }) { score += 2 }
            if let year, let date = result.releaseDate ?? result.firstAirDate, let found = Int(date.prefix(4)) {
                if found == year { score += 3 } else if abs(found - year) == 1 { score += 1 } else { score -= 2 }
            }
            return score
        }
        let best = results.enumerated().max { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa == sb ? a.offset > b.offset : sa < sb
        }!.element
        return try await metadata(for: best, type: type)
    }

    private func searchResults(title: String, year: Int?, type: TMDBMetadata.MediaType) async throws -> [Result] {
        var query = ["query": title]
        if let year { query[type == .movie ? "year" : "first_air_date_year"] = String(year) }
        let envelope: SearchEnvelope = try await get("search/\(type.rawValue)", query)
        return envelope.results
    }

    /// Case, punctuation and articles out: "Titan: The OceanGate Disaster" ≈ "Titan the Oceangate Disaster".
    static func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func metadata(for result: Result, type: TMDBMetadata.MediaType) async throws -> TMDBMetadata {
        var counts: [Int: Int] = [:]
        if type == .tv {
            let show: ShowDetails = try await get("tv/\(result.id)", [:])
            for season in show.seasons where season.seasonNumber > 0 {
                counts[season.seasonNumber] = season.episodeCount
            }
        }
        let externalIDs: ExternalIDs? = try? await get("\(type.rawValue)/\(result.id)/external_ids", [:])
        let date = result.releaseDate ?? result.firstAirDate
        return TMDBMetadata(
            tmdbID: result.id,
            mediaType: type,
            title: result.title ?? result.name ?? "",
            year: date.flatMap { Int($0.prefix(4)) },
            posterPath: result.posterPath,
            overview: result.overview,
            voteAverage: result.voteAverage,
            voteCount: result.voteCount,
            imdbID: externalIDs?.imdbID,
            episodeCounts: counts,
            fetchedAt: Date()
        )
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        guard !apiKey.isEmpty else { throw ClientError.missingKey }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.statusMessage
            throw ClientError.requestFailed(message ?? "HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct FindEnvelope: Decodable {
        let movieResults: [Result]
        let tvResults: [Result]
        enum CodingKeys: String, CodingKey { case movieResults = "movie_results", tvResults = "tv_results" }
    }
    private struct SearchEnvelope: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let id: Int
        let title: String?
        let name: String?
        let originalTitle: String?
        let originalName: String?
        let posterPath: String?
        let overview: String?
        let voteAverage: Double?
        let voteCount: Int?
        let releaseDate: String?
        let firstAirDate: String?
        enum CodingKeys: String, CodingKey {
            case id, title, name, overview
            case originalTitle = "original_title"
            case originalName = "original_name"
            case posterPath = "poster_path"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
            case voteAverage = "vote_average"
            case voteCount = "vote_count"
        }
    }
    private struct ExternalIDs: Decodable {
        let imdbID: String?
        enum CodingKeys: String, CodingKey { case imdbID = "imdb_id" }
    }
    private struct ShowDetails: Decodable {
        let seasons: [Season]
        struct Season: Decodable {
            let seasonNumber: Int
            let episodeCount: Int
            enum CodingKeys: String, CodingKey { case seasonNumber = "season_number", episodeCount = "episode_count" }
        }
    }
    private struct ErrorEnvelope: Decodable {
        let statusMessage: String?
        enum CodingKeys: String, CodingKey { case statusMessage = "status_message" }
    }
}

/// Posters, once. Memory + `~/Library/Caches/Cargo/posters`.
@MainActor
final class PosterCache {
    static let shared = PosterCache()
    private var memory: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("Cargo/posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func cachedImage(for url: URL) -> NSImage? {
        memory[url]
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory[url] { return cached }
        let file = directory.appendingPathComponent(url.lastPathComponent)
        if let image = NSImage(contentsOf: file) {
            memory[url] = image
            return image
        }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return nil }
            try? data.write(to: file)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory[url] = image }
        return image
    }
}
