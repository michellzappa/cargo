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

    func search(title: String, year: Int?, type: TMDBMetadata.MediaType) async throws -> TMDBMetadata {
        var query = ["query": title]
        if let year { query[type == .movie ? "year" : "first_air_date_year"] = String(year) }
        let envelope: SearchEnvelope = try await get("search/\(type.rawValue)", query)
        guard let first = envelope.results.first else { throw ClientError.notFound }
        return try await metadata(for: first, type: type)
    }

    private func metadata(for result: Result, type: TMDBMetadata.MediaType) async throws -> TMDBMetadata {
        var counts: [Int: Int] = [:]
        if type == .tv {
            let show: ShowDetails = try await get("tv/\(result.id)", [:])
            for season in show.seasons where season.seasonNumber > 0 {
                counts[season.seasonNumber] = season.episodeCount
            }
        }
        let date = result.releaseDate ?? result.firstAirDate
        return TMDBMetadata(
            tmdbID: result.id,
            mediaType: type,
            title: result.title ?? result.name ?? "",
            year: date.flatMap { Int($0.prefix(4)) },
            posterPath: result.posterPath,
            overview: result.overview,
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
        let posterPath: String?
        let overview: String?
        let releaseDate: String?
        let firstAirDate: String?
        enum CodingKeys: String, CodingKey {
            case id, title, name, overview
            case posterPath = "poster_path"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
        }
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
